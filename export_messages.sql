/*

To run this script:

CD %APPDATA%\iMazing\Backups\iMazing.Versions\Versions\00008110-000251E00CF9401E\
CD <the backup folder you want to extract from>
sqlite3
.read "<source file location>\\export_messages.sql"

*/

-- ========================================

-- Reference information:
-- Sources
-- 		iPhone Wiki "Messages"
-- 			https://www.theiphonewiki.com/wiki/Messages
-- 		Steve Morse, "Analyzing iMessage conversations"
-- 			https://stmorse.github.io/journal/iMessage.html
-- Details
-- 		The iTunes Backup filename of sms.db is 3d0d7e5fb2ce288813306e4d4636395e047a3d28.
-- 			(https://www.theiphonewiki.com/wiki/Messages#Serialization)
-- 

-- Make it easy to re-run this script
drop table if exists "results" ;
drop table if exists "people" ;
detach database message_db ;
detach database person_db ;

-- Mount the iPhone databases
attach database ".\3d\3d0d7e5fb2ce288813306e4d4636395e047a3d28" as message_db ;
attach database ".\31\31bb7ba8914766d4ba40d6dfb6113c8b614be442"	as person_db ;

-- Get the address book listings for users listed in the message database
create table "people" as
	select *
		from
			person_db."ABPersonFullTextSearch_content",
			message_db."handle"		
	where
			"ABPersonFullTextSearch_content"."c16Phone" like ('%' || "handle"."id" || '%')
			-- or
			-- "ABPersonFullTextSearch_content"."c17Email" like ???
			-- or
			-- ...
	;

-- Start building the extract table
create table "results"
	as
		select
			"message".*,
			"chat_message_join"."chat_id" as "conversation_id"
		from
			message_db."message",
			message_db."chat_message_join"
		where "message"."ROWID" = "chat_message_join"."message_id"
	;

alter table "results" rename column "date"           to "date_utc" ;
alter table "results" rename column "date_delivered" to "date_delivered_utc" ;
alter table "results" rename column "date_edited"    to "date_edited_utc" ;
alter table "results" rename column "date_read"      to "date_read_utc" ;
alter table "results" rename column "date_retracted" to "date_retracted_utc" ;
alter table "results" rename column "ROWID"          to "message_id" ;

-- iPhone databases store timestamps as integer microseconds since 2001-01-01 00:00:00.
-- Recode them as dates via coercion to the Unix epoch (seconds since 1970-01-01 00:00:00).
update "results" set "date_utc"           = datetime("date_utc"           / 1000000000 + strftime('%s','2001-01-01'), 'unixepoch')
	where "date_utc"           <> 0 ;
update "results" set "date_delivered_utc" = datetime("date_delivered_utc" / 1000000000 + strftime('%s','2001-01-01'), 'unixepoch')
	where "date_delivered_utc" <> 0 ;
update "results" set "date_edited_utc"    = datetime("date_edited_utc"    / 1000000000 + strftime('%s','2001-01-01'), 'unixepoch')
	where "date_edited_utc"    <> 0 ;
update "results" set "date_read_utc"      = datetime("date_read_utc"      / 1000000000 + strftime('%s','2001-01-01'), 'unixepoch')
	where "date_read_utc"      <> 0 ;
update "results" set "date_retracted_utc" = datetime("date_retracted_utc" / 1000000000 + strftime('%s','2001-01-01'), 'unixepoch')
	where "date_retracted_utc" <> 0 ;

-- Add the identity columns and set their data from the contacts
-- Also rewrite USA phone numbers from "+1aaapppnnnn" to "+1 aaa-ppp-nnnn".
alter table "results" add column "first" ;
alter table "results" add column "middle" ;
alter table "results" add column "last" ;
alter table "results" add column "my_phone" ;
alter table "results" add column "other_phone" ;

update "results"
	set
		( "first", "middle", "last", "other_phone" ) = ( 
			select "c0First", "c2Middle", "c1Last", 
				( substr("id", 1, 2) || ' ' || substr("id", 3, 3) || '-' || substr("id", 8, 3) || '-' || substr("id", 9) ) -- +1 aaa-ppp-nnnn
			from "people" where "handle_id" = "people"."ROWID" 
		),
		"my_phone" = ( substr("account", 3, 2) || ' ' || substr("account", 5, 3) || '-' || substr("account", 8, 3) || '-' || substr("account", 11) )	
	;

-- Set the sender and receiver info.
alter table "results" add column "from";
alter table "results" add column "to";
alter table "results" add column "from_phone";
alter table "results" add column "to_phone";

update "results"
	set
		"from"       = 'Ross',
		"from_phone" = "my_phone",
		"to"         = "first",
		"to_phone"   = "other_phone"
	where "is_from_me" = 1
	;

update "results"
	set
		"from"       = "first",
		"from_phone" = "other_phone",
		"to"         = 'Ross',
		"to_phone"   = "my_phone"
	where "is_from_me" = 0
	;

-- Dump the data we want to a CSV file
.mode csv
.headers on
.once messages.csv

select
	"conversation_id", "message_id", "date_utc", "from", "from_phone", "to", "to_phone", "text"
	from "results"
	order by "date_utc"
	;

-- ========================================

.mode csv
.headers on
.once message_attachments.csv

select
	"message"."ROWID" as "message_id",
	"attachment".*
	from 
		message_db."message",
		message_db."attachment",
		message_db."message_attachment_join"
	where
		"attachment"."ROWID" = "message_attachment_join"."attachment_id"
		and
		"message"."ROWID" = "message_attachment_join"."message_id"
	;

-- ========================================

.headers off
.mode list
