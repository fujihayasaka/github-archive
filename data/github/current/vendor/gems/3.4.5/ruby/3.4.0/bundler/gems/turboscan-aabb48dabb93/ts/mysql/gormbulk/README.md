# Gorm Bulk Insert

This is a 'fork' of
https://github.com/t-tiger/gorm-bulk-insert/tree/v1.3.0 so that we can
make some modifications to return the
`last_insert_id` so that we can bulk insert rows to a table and then
subsequently to other tables that have a foreign key reference to the
first table.

I did not try to upstream this at this time for a few reasons:

1. The technique is MySQL-specific: batch `INSERT` statements are not
   guaranteed to use a contiguous sequence of auto-incremented ids in
   other databases, and `last_insert_id()` may be not be the first
   used id from such a statement.
2. GORMv2 [will have
   support](https://github.com/jinzhu/gorm/issues/255#issuecomment-590287329)
   for bulk inserts, although we don't know if/when that will be
   released.
3. We may switch to `sqlboiler` or another database library.
