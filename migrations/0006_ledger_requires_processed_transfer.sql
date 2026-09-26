-- Ledger entries represent the settled accounting record of a completed
-- transfer. Attaching an entry to a PENDING or FAILED transfer would let a
-- direct database writer move money without a PROCESSED transfer, violating
-- the documented database-enforced invariant.
--
-- The existing composite FK (ledger_transfer_amount_fk) pins the amount but
-- does not constrain the transfer's status. This trigger closes that gap.
--
-- The trigger is declared DEFERRABLE INITIALLY IMMEDIATE so that:
--   - By default it fires at statement time, after the FK constraint, so a
--     direct insert referencing a non-existent transfer surfaces the FK's
--     23503 (foreign_key_violation) rather than this trigger's 23514.
--   - Inside the application's transfer transaction, InTx defers it with
--     SET CONSTRAINTS so the check runs at COMMIT, by which time MarkProcessed
--     has already set the transfer to PROCESSED in the same transaction.
CREATE FUNCTION enforce_ledger_transfer_processed()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    transfer_status text;
BEGIN
    SELECT status
      INTO transfer_status
      FROM transfers
     WHERE id = NEW.transfer_id;

    -- Leave missing transfers to the existing composite FK so it retains its
    -- precise referential-integrity error message.
    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    IF transfer_status <> 'PROCESSED' THEN
        RAISE EXCEPTION USING
            ERRCODE = '23514',
            MESSAGE = 'ledger entries may only be created for PROCESSED transfers';
    END IF;

    RETURN NEW;
END;
$$;

CREATE CONSTRAINT TRIGGER ledger_entries_require_processed_transfer
AFTER INSERT OR UPDATE ON ledger_entries
DEFERRABLE INITIALLY IMMEDIATE
FOR EACH ROW
EXECUTE FUNCTION enforce_ledger_transfer_processed();
