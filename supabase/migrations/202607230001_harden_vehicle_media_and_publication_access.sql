drop policy if exists vehicle_photos_add on public.vehicle_photos;
create policy vehicle_photos_add on public.vehicle_photos
for insert to authenticated
with check (
  uploaded_by = (select auth.uid())
  and exists (
    select 1 from public.vehicles v
    where v.id = vehicle_photos.vehicle_id
      and private.can_access_vehicle(v.dealership_id, v.id)
  )
);

drop policy if exists vehicle_photos_read on public.vehicle_photos;
create policy vehicle_photos_read on public.vehicle_photos
for select to authenticated
using (
  exists (
    select 1 from public.vehicles v
    where v.id = vehicle_photos.vehicle_id
      and private.can_access_vehicle(v.dealership_id, v.id)
  )
);

drop policy if exists publications_create on public.publications;
create policy publications_create on public.publications
for insert to authenticated
with check (
  published_by = (select auth.uid())
  and private.can_access_vehicle(dealership_id, vehicle_id)
  and exists (
    select 1 from public.vehicles v
    where v.id = publications.vehicle_id
      and v.dealership_id = publications.dealership_id
  )
);

create index if not exists bootstrap_masters_consumed_by_idx
  on private.bootstrap_masters(consumed_by);
