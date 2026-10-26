-- ============================================================
-- 宿舍焕新 v3：两段式供应链改造（旧货池 → 管理员审核 → 社团认领 → 成品上架）
-- 幂等脚本，可重复运行。运行前请先关闭浏览器翻译！
-- ============================================================

-- ---------- 0. 关键修复：回填缺失的用户档案 ----------
-- 之前「三角色界面一样」的根因：profiles 里没有记录，前端读不到 role，全部按 student 处理
insert into public.profiles (id, nickname)
select u.id, split_part(u.email, '@', 1)
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null;

-- 允许用户自己补建档案（万一触发器没跑到）
drop policy if exists "profiles_insert_self" on profiles;
create policy "profiles_insert_self" on profiles for insert to authenticated
  with check (auth.uid() = id);

-- ---------- 1. 旧货库存表（所有待改造物品的唯一入口） ----------
create table if not exists stock_items (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  category    text default '其他',
  description text,
  images      jsonb default '[]'::jsonb,
  source      text not null default 'student' check (source in ('student','offline')),
  post_id     uuid references recycle_posts(id) on delete set null, -- 来源：学生投稿
  cost        numeric(10,2) default 0,   -- 线下进货成本
  status      text not null default 'pending'
              check (status in ('pending','available','onsale','assigned','converted')),
              -- pending 待管理员审核 / available 开放给社团认领
              -- onsale 管理员翻新后已直接上架 / assigned 社团改造中 / converted 社团已改造成品
  created_by  uuid references profiles(id) on delete set null,
  created_at  timestamptz default now()
);

-- 学生投稿 → 自动进入旧货池（待审核）
create or replace function public.post_to_stock() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.stock_items (title, category, description, images, source, post_id, created_by, status)
  values (new.title, new.category, new.description, new.images, 'student', new.id, new.author, 'pending');
  return new;
end $$;

drop trigger if exists posts_to_stock on recycle_posts;
create trigger posts_to_stock after insert on recycle_posts
  for each row execute function public.post_to_stock();

-- ---------- 2. 认领申请表（社团向管理员申请领取旧货） ----------
create table if not exists claims (
  id         uuid primary key default gen_random_uuid(),
  stock_id   uuid not null references stock_items(id) on delete cascade,
  member     uuid not null references profiles(id) on delete cascade,
  note       text,
  status     text not null default 'new'
             check (status in ('new','accepted','delivered','done')),
             -- new 申请中 / accepted 已通过 / delivered 已发货 / done 已改造完成
  created_at timestamptz default now(),
  unique (stock_id, member)   -- 同一人同一件旧货只申请一次
);

-- ---------- 3. 成品表扩展：来源旧货 + 创作者 + 上架状态 + 商品类型 ----------
alter table products add column if not exists stock_id uuid references stock_items(id) on delete set null;
alter table products add column if not exists creator  uuid references profiles(id) on delete set null;
alter table products add column if not exists status   text not null default 'online';
-- kind 区分两类商品：refurbished 管理员筛选翻新后的二手物品 / diy DIY社团创意成品
alter table products add column if not exists kind text not null default 'diy';
update products set kind = 'diy' where kind is null or kind = '';

-- 历史数据兜底：把老商品标记为上线
update products set status = 'online' where status is null;

-- ---------- 4. 重写 RLS 策略：角色看到的数据严格隔离 ----------
alter table stock_items enable row level security;
alter table claims      enable row level security;

-- 旧货池：管理员全看；社团只能看已审核通过的（pending 看不到）；学生完全看不到
drop policy if exists "stock_read" on stock_items;
create policy "stock_read" on stock_items for select to authenticated
  using (
    public.is_admin()
    or (public.my_role() = 'member' and status <> 'pending')
    or (created_by = auth.uid())          -- 投稿人能看到自己投稿的处理进度
  );

-- 线下进货只能管理员录入
drop policy if exists "stock_insert_admin" on stock_items;
create policy "stock_insert_admin" on stock_items for insert to authenticated
  with check (public.is_admin());

-- 审核/发货：管理员可改任意；社团只能把已认领的旧货标记为已改造
drop policy if exists "stock_update" on stock_items;
create policy "stock_update" on stock_items for update to authenticated
  using (public.is_admin() or (public.my_role() = 'member' and status in ('available','assigned')))
  with check (public.is_admin() or (public.my_role() = 'member' and status in ('available','assigned','converted')));

drop policy if exists "stock_delete_admin" on stock_items;
create policy "stock_delete_admin" on stock_items for delete to authenticated
  using (public.is_admin());

-- 认领申请：社团只能看/建自己的；管理员全部可见可处理
drop policy if exists "claims_read" on claims;
create policy "claims_read" on claims for select to authenticated
  using (member = auth.uid() or public.is_admin());

drop policy if exists "claims_insert_member" on claims;
create policy "claims_insert_member" on claims for insert to authenticated
  with check (
    public.my_role() = 'member' and auth.uid() = member
    and exists (select 1 from stock_items s where s.id = stock_id and s.status = 'available')
  );

drop policy if exists "claims_update_admin" on claims;
create policy "claims_update_admin" on claims for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

drop policy if exists "claims_update_own" on claims;
create policy "claims_update_own" on claims for update to authenticated
  using (auth.uid() = member and status = 'delivered')
  with check (auth.uid() = member and status = 'done');

-- 商品：学生/游客只能看到「已上架」成品；社团和管理员能看到全部
drop policy if exists "products_read_all" on products;
drop policy if exists "products_read_public" on products;
create policy "products_read_public" on products for select
  using (status = 'online' or public.my_role() in ('member','admin'));

-- 社团上架成品时 creator 必须是自己
drop policy if exists "products_write_member" on products;
create policy "products_write_member" on products for insert to authenticated
  with check (public.is_member_or_admin() and creator = auth.uid());

drop policy if exists "products_update_member" on products;
create policy "products_update_member" on products for update to authenticated
  using (public.is_admin() or creator = auth.uid())
  with check (public.is_admin() or creator = auth.uid());

-- ---------- 5. 演示用的线下进货数据（表为空时才插入） ----------
insert into stock_items (title, category, description, source, cost, status)
select * from (values
  ('二手实木书架（校友捐赠）', '家具', '结构完好，漆面有磨损，适合打磨翻新成宿舍置物架。', 'offline', 15.00, 'available'),
  ('旧台灯 3 台（跳蚤市场收购）', '电器', '灯罩发黄、线路正常，可改造成氛围小夜灯。', 'offline', 9.00, 'available'),
  ('旧牛仔布窗帘', '织物', '布料厚实，可改造成收纳袋或地垫。', 'offline', 5.00, 'available')
) as v(title, category, description, source, cost, status)
where not exists (select 1 from stock_items);
