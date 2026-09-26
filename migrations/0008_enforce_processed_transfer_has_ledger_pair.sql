-- A PROCESSED transfer must have exactly one DEBIT and one CREDIT in
-- ledger_entries, each equal to the transfer's amount. Migration 0006 prevents
-- ledger entries from being attached to non-PROCESSED transfers; this trigger
-- closes the inverse gap: it prevents a transfer from becoming (or remaining)
-- PROCESSED without the required ledger pair.
--
-- The trigger is DEFERRABLE INITIALLY DEFERRED so it fires at COMMIT rather
-- than at the UPDATE statement. The application's transfer transaction writes
-- the ledger pair first and then marks the transfer PROCESSED in the same
-- transaction (see service/transfer.go); a statement-time trigger would fire
-- before the ledger rows exist and would always reject the update. At COMMIT
-- both writes have landed, so the check sees the complete picture.
--
-- InTx already issues SET CONSTRAINTS ALL DEFERRED as part of
-- SetLocalTransactionTimeoutsSQL, so no additional application change is
-- needed.
CREATE FUNCTION enforce_processed_transfer_has_ledger_pair()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    debit_count  int;
    credit_count int;
BEGIN
    -- Only relevant when the transfer is transitioning to or remaining PROCESSED.
    IF NEW.status <> 'PROCESSED' THEN
        RETURN NEW;
    END IF;

    SELECT
        count(*) FILTER (WHERE entry_type = 'DEBIT'),
        count(*) FILTER (WHERE entry_type = 'CREDIT')
      INTO debit_count, credit_count
      FROM ledger_entries
     WHERE transfer_id = NEW.id
       AND amount = NEW.amount;

    IF debit_count <> 1 OR credit_count <> 1 THEN
        RAISE EXCEPTION USING
            ERRCODE = '23514',
            MESSAGE = format(
                'PROCESSED transfer %s must have exactly 1 DEBIT and 1 CREDIT '
                'with amount %s; found %s DEBIT(s) and %s CREDIT(s)',
                NEW.id, NEW.amount, debit_count, credit_count
            );
    END IF;

    RETURN NEW;
END;
$$;

CREATE CONSTRAINT TRIGGER transfers_processed_requires_ledger_pair
AFTER INSERT OR UPDATE ON transfers
DEFERRABLE INITIALLY DEFERRED
FOR EACH ROW
EXECUTE FUNCTION enforce_processed_transfer_has_ledger_pair();
