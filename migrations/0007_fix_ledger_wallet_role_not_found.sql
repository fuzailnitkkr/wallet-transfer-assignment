-- The enforce_ledger_wallet_role trigger function was deployed without a
-- NOT FOUND guard on some databases (the guard was added to 0004 after initial
-- deployment). Without the guard, an insert referencing a non-existent
-- transfer_id causes the DEBIT/CREDIT check to compare wallet_id against NULL,
-- which is always DISTINCT, raising a misleading 23514 instead of allowing the
-- composite FK to raise its precise 23503 (foreign_key_violation).
--
-- This migration re-creates the function with the correct guard so that all
-- databases converge on the same behaviour regardless of when 0004 was applied.
CREATE OR REPLACE FUNCTION enforce_ledger_wallet_role()
RETURNS trigger
LANGUAGE plpgsql
AS $$
DECLARE
    source_wallet text;
    destination_wallet text;
BEGIN
    SELECT from_wallet_id, to_wallet_id
      INTO source_wallet, destination_wallet
      FROM transfers
     WHERE id = NEW.transfer_id;

    -- Leave missing transfers to the existing composite foreign key so that
    -- it retains its precise referential-integrity error.
    IF NOT FOUND THEN
        RETURN NEW;
    END IF;

    IF (NEW.entry_type = 'DEBIT' AND NEW.wallet_id IS DISTINCT FROM source_wallet)
       OR (NEW.entry_type = 'CREDIT' AND NEW.wallet_id IS DISTINCT FROM destination_wallet) THEN
        RAISE EXCEPTION USING
            ERRCODE = '23514',
            MESSAGE = 'ledger entry wallet does not match transfer role';
    END IF;

    RETURN NEW;
END;
$$;
