revoke truncate, trigger, references on all tables in schema public from authenticated;
revoke all privileges on all tables in schema public from anon;

drop policy if exists notifications_own_read on public.notifications;
create policy notifications_own_read on public.notifications
for select to authenticated
using (recipient_id = (select auth.uid()));
