-- Once ledger entries exist for a transfer, its from_wallet_id and to_wallet_id
-- become part of an immutable audit record (every ledger row is tied to those
-- roles). This trigger prevents a direct UPDATE from silently detaching a
-- transfer's wallet roles from the entries that reference it.
--
-- The enforce_ledger_wallet_role trigger (migration 0004) only fires on
-- ledger_entries INSERT/UPDATE, leaving a gap: an UPDATE on transfers after
-- entries exist would not be caught. This trigger closes that gap.
CREATE FUNCTION prevent_transfer_wallet_update()
RETURNS trigger
LANGUAGE plpgsql
AS $$
BEGIN
    -- Allow changes that do not touch the wallet columns.
    IF (NEW.from_wallet_id IS NOT DISTINCT FROM OLD.from_wallet_id
        AND NEW.to_wallet_id IS NOT DISTINCT FROM OLD.to_wallet_id) THEN
        RETURN NEW;
    END IF;

    -- Reject the update if any ledger entries reference this transfer.
    IF EXISTS (SELECT 1 FROM ledger_entries WHERE transfer_id = OLD.id) THEN
        RAISE EXCEPTION USING
            ERRCODE = '23514',
            MESSAGE = 'cannot change wallet IDs on a transfer that already has ledger entries';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER transfers_immutable_wallet_ids
BEFORE UPDATE ON transfers
FOR EACH ROW
EXECUTE FUNCTION prevent_transfer_wallet_update();
