-- ============================================================
-- 宿舍焕新 · 完整数据库脚本（唯一需要运行的文件）
-- ------------------------------------------------------------
-- 用法：Supabase → SQL Editor → 新建查询 → 全部粘贴 → Run
-- 特性：全新项目可一次建好；已建过的项目重复运行也不会报错（幂等）
-- 包含：用户档案/角色、闲置投稿、旧货池、认领申请、商品、订单、
--       收藏、转赠、家园状态、积分、热门榜、存储桶、全部 RLS 策略、示例数据
-- ============================================================

-- ============================================================
-- 第一部分：基础类型与用户档案
-- ============================================================

-- 角色枚举（已存在则跳过）
do $$ begin
  create type app_role as enum ('student', 'member', 'admin');
exception when duplicate_object then null; end $$;

-- 用户档案
create table if not exists profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  nickname    text,
  role        app_role not null default 'student',
  points      int not null default 0,
  created_at  timestamptz default now()
);

-- 注册自动建档
create or replace function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, nickname)
  values (new.id, coalesce(new.raw_user_meta_data->>'nickname', split_part(new.email, '@', 1)))
  on conflict (id) do nothing;
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- 角色判断（RLS 里调用，前端无法伪造）
create or replace function public.my_role() returns app_role
language sql security definer set search_path = public stable as $$
  select role from public.profiles where id = auth.uid();
$$;

create or replace function public.is_admin() returns boolean
language sql security definer set search_path = public stable as $$
  select public.my_role() = 'admin';
$$;

create or replace function public.is_member_or_admin() returns boolean
language sql security definer set search_path = public stable as $$
  select public.my_role() in ('member', 'admin');
$$;

-- ============================================================
-- 第二部分：业务表
-- ============================================================

-- 1) 学生闲置投稿
create table if not exists recycle_posts (
  id          uuid primary key default gen_random_uuid(),
  author      uuid not null references profiles(id) on delete cascade,
  title       text not null,
  category    text default '其他',
  description text,
  images      jsonb default '[]'::jsonb,
  status      text default 'pending',   -- pending 审核中 / claimed 已进入旧货池 / done 已完成
  created_at  timestamptz default now()
);

-- 2) 旧货池（学生投稿 + 线下进货）
create table if not exists stock_items (
  id          uuid primary key default gen_random_uuid(),
  title       text not null,
  category    text default '其他',
  description text,
  images      jsonb default '[]'::jsonb,
  source      text not null default 'student' check (source in ('student','offline')),
  post_id     uuid references recycle_posts(id) on delete set null,
  cost        numeric(10,2) default 0,
  status      text not null default 'pending'
              check (status in ('pending','available','onsale','assigned','converted')),
  created_by  uuid references profiles(id) on delete set null,
  created_at  timestamptz default now()
);

-- 学生投稿 → 自动进入旧货池待审
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

-- 3) 社团认领申请
create table if not exists claims (
  id         uuid primary key default gen_random_uuid(),
  stock_id   uuid not null references stock_items(id) on delete cascade,
  member     uuid not null references profiles(id) on delete cascade,
  note       text,
  status     text not null default 'new' check (status in ('new','accepted','delivered','done')),
  created_at timestamptz default now(),
  unique (stock_id, member)
);

-- 4) 商品（翻新二手 / 社团改造成品）
create table if not exists products (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  zone         text not null default 'floor',
  price        numeric(10,2) not null default 0,
  description  text,
  story        text,
  image_before text,
  image_after  text,
  created_at   timestamptz default now()
);
alter table products add column if not exists stock_id uuid references stock_items(id) on delete set null;
alter table products add column if not exists creator  uuid references profiles(id) on delete set null;
alter table products add column if not exists status   text not null default 'online';
alter table products add column if not exists kind     text not null default 'diy';
alter table products add column if not exists process_images jsonb default '[]'::jsonb;

-- 5) 购买意向（无真实支付）
create table if not exists orders (
  id         uuid primary key default gen_random_uuid(),
  product_id uuid not null references products(id) on delete cascade,
  buyer      uuid not null references profiles(id) on delete cascade,
  status     text default 'new',   -- new 新意向 / contacted 已联系
  created_at timestamptz default now(),
  unique (product_id, buyer)
);

-- 6) 收藏夹
create table if not exists favorites (
  user_id    uuid not null references profiles(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, product_id)
);

-- 7) 转赠记录（二手物品再次流转 → 双人家园关系来源）
create table if not exists transfers (
  id         uuid primary key default gen_random_uuid(),
  product_id uuid not null references products(id) on delete cascade,
  from_user  uuid not null references profiles(id) on delete cascade,
  to_user    uuid not null references profiles(id) on delete cascade,
  message    text,
  status     text not null default 'pending' check (status in ('pending','accepted','declined')),
  created_at timestamptz default now(),
  check (from_user <> to_user)
);

-- 8) 家园状态
create table if not exists home_state (
  user_id    uuid primary key references profiles(id) on delete cascade,
  level      int not null default 0,
  theme      text default 'mint',
  intimacy   int not null default 0,
  partner    uuid references profiles(id) on delete set null,
  has_baby   boolean not null default false,
  updated_at timestamptz default now()
);

-- ============================================================
-- 第三部分：自动积分 + 热门榜
-- ============================================================

-- 投稿 +10 分，购买意向 +5 分
create or replace function public.add_points() returns trigger
language plpgsql security definer set search_path = public as $$
declare delta int;
begin
  delta := case TG_TABLE_NAME
    when 'recycle_posts' then 10
    when 'orders' then 5
    else 0 end;
  update public.profiles set points = points + delta where id = auth.uid();
  return new;
end $$;

drop trigger if exists posts_add_points on recycle_posts;
create trigger posts_add_points after insert on recycle_posts
  for each row execute function public.add_points();

drop trigger if exists orders_add_points on orders;
create trigger orders_add_points after insert on orders
  for each row execute function public.add_points();

-- 热门趋势：购买意向×3 + 收藏×1（只返回数字，不泄露订单明细）
create or replace function public.hot_products()
returns table (product_id uuid, order_count bigint, fav_count bigint, hot_score bigint)
language sql security definer set search_path = public stable as $$
  select p.id,
         coalesce(o.cnt, 0)::bigint,
         coalesce(f.cnt, 0)::bigint,
         (coalesce(o.cnt, 0) * 3 + coalesce(f.cnt, 0))::bigint
  from products p
  left join (select product_id, count(*) cnt from orders group by product_id) o on o.product_id = p.id
  left join (select product_id, count(*) cnt from favorites group by product_id) f on f.product_id = p.id
  where p.status = 'online';
$$;
grant execute on function public.hot_products() to anon, authenticated;

-- 好友视图：与我发生过「已接受转赠」的人
create or replace view my_transfer_friends
with (security_invoker = true) as
select t.from_user as me, t.to_user as friend_id, p.nickname, t.product_id, t.created_at
from transfers t join profiles p on p.id = t.to_user
where t.status = 'accepted'
union
select t.to_user as me, t.from_user as friend_id, p.nickname, t.product_id, t.created_at
from transfers t join profiles p on p.id = t.from_user
where t.status = 'accepted';
grant select on my_transfer_friends to authenticated;

-- ============================================================
-- 第四部分：RLS 权限策略（真正的后端鉴权在这里）
-- ============================================================
alter table profiles      enable row level security;
alter table recycle_posts enable row level security;
alter table stock_items   enable row level security;
alter table claims        enable row level security;
alter table products      enable row level security;
alter table orders        enable row level security;
alter table favorites     enable row level security;
alter table transfers     enable row level security;
alter table home_state    enable row level security;

-- ---------- profiles ----------
drop policy if exists "profiles_read" on profiles;
create policy "profiles_read" on profiles for select using (true);

drop policy if exists "profiles_insert_self" on profiles;
create policy "profiles_insert_self" on profiles for insert to authenticated
  with check (auth.uid() = id);

-- 本人只能改昵称（角色不能自己改），管理员可以改任何人的角色
drop policy if exists "profiles_update_self" on profiles;
create policy "profiles_update_self" on profiles for update to authenticated
  using (auth.uid() = id) with check (auth.uid() = id and role = public.my_role());

drop policy if exists "profiles_update_role_admin" on profiles;
create policy "profiles_update_role_admin" on profiles for update to authenticated
  using (public.is_admin()) with check (public.is_admin());

-- ---------- recycle_posts ----------
drop policy if exists "posts_read_auth" on recycle_posts;
create policy "posts_read_auth" on recycle_posts for select to authenticated using (true);

drop policy if exists "posts_insert_own" on recycle_posts;
create policy "posts_insert_own" on recycle_posts for insert to authenticated
  with check (auth.uid() = author);

drop policy if exists "posts_update_own" on recycle_posts;
create policy "posts_update_own" on recycle_posts for update to authenticated
  using (auth.uid() = author or public.is_member_or_admin())
  with check (auth.uid() = author or public.is_member_or_admin());

drop policy if exists "posts_delete_own" on recycle_posts;
create policy "posts_delete_own" on recycle_posts for delete to authenticated
  using (auth.uid() = author or public.is_admin());

-- ---------- stock_items（旧货池） ----------
-- 管理员全看；社团只看到已审核通过的；学生只能看到自己投稿的
drop policy if exists "stock_read" on stock_items;
create policy "stock_read" on stock_items for select to authenticated
  using (
    public.is_admin()
    or (public.my_role() = 'member' and status <> 'pending')
    or (created_by = auth.uid())
  );

drop policy if exists "stock_insert_admin" on stock_items;
create policy "stock_insert_admin" on stock_items for insert to authenticated
  with check (public.is_admin());

drop policy if exists "stock_update" on stock_items;
create policy "stock_update" on stock_items for update to authenticated
  using (public.is_admin() or (public.my_role() = 'member' and status in ('available','assigned')))
  with check (public.is_admin() or (public.my_role() = 'member' and status in ('available','assigned','converted')));

drop policy if exists "stock_delete_admin" on stock_items;
create policy "stock_delete_admin" on stock_items for delete to authenticated
  using (public.is_admin());

-- ---------- claims（认领申请） ----------
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

-- ---------- products ----------
-- 游客/学生只看到在售商品；社团和管理员看到全部
drop policy if exists "products_read_all" on products;
drop policy if exists "products_read_public" on products;
create policy "products_read_public" on products for select
  using (status = 'online' or public.my_role() in ('member','admin'));

drop policy if exists "products_write_member" on products;
create policy "products_write_member" on products for insert to authenticated
  with check (public.is_member_or_admin() and creator = auth.uid());

drop policy if exists "products_update_member" on products;
create policy "products_update_member" on products for update to authenticated
  using (public.is_admin() or creator = auth.uid())
  with check (public.is_admin() or creator = auth.uid());

drop policy if exists "products_delete_admin" on products;
create policy "products_delete_admin" on products for delete to authenticated
  using (public.is_admin());

-- ---------- orders ----------
drop policy if exists "orders_read" on orders;
create policy "orders_read" on orders for select to authenticated
  using (auth.uid() = buyer or public.is_member_or_admin());

drop policy if exists "orders_insert_own" on orders;
create policy "orders_insert_own" on orders for insert to authenticated
  with check (auth.uid() = buyer);

drop policy if exists "orders_update_staff" on orders;
create policy "orders_update_staff" on orders for update to authenticated
  using (public.is_member_or_admin()) with check (public.is_member_or_admin());

-- ---------- favorites ----------
drop policy if exists "fav_own_all" on favorites;
create policy "fav_own_all" on favorites for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------- transfers ----------
drop policy if exists "transfers_read" on transfers;
create policy "transfers_read" on transfers for select to authenticated
  using (auth.uid() = from_user or auth.uid() = to_user or public.is_admin());

drop policy if exists "transfers_insert" on transfers;
create policy "transfers_insert" on transfers for insert to authenticated
  with check (auth.uid() = from_user);

drop policy if exists "transfers_update_receiver" on transfers;
create policy "transfers_update_receiver" on transfers for update to authenticated
  using (auth.uid() = to_user) with check (auth.uid() = to_user);

-- ---------- home_state ----------
drop policy if exists "home_read" on home_state;
create policy "home_read" on home_state for select to authenticated
  using (auth.uid() = user_id or auth.uid() = partner);

drop policy if exists "home_upsert_own" on home_state;
create policy "home_upsert_own" on home_state for insert to authenticated
  with check (auth.uid() = user_id);

drop policy if exists "home_update_own" on home_state;
create policy "home_update_own" on home_state for update to authenticated
  using (auth.uid() = user_id or auth.uid() = partner)
  with check (auth.uid() = user_id or auth.uid() = partner);

-- ============================================================
-- 第五部分：图片存储桶
-- ============================================================
insert into storage.buckets (id, name, public) values ('recycle-images', 'recycle-images', true)
on conflict (id) do nothing;

drop policy if exists "storage_read_public" on storage.objects;
create policy "storage_read_public" on storage.objects for select
  using (bucket_id = 'recycle-images');

drop policy if exists "storage_upload_auth" on storage.objects;
create policy "storage_upload_auth" on storage.objects for insert to authenticated
  with check (bucket_id = 'recycle-images' and (storage.foldername(name))[1] = auth.uid()::text);

drop policy if exists "storage_delete_own" on storage.objects;
create policy "storage_delete_own" on storage.objects for delete to authenticated
  using (bucket_id = 'recycle-images' and (storage.foldername(name))[1] = auth.uid()::text);

-- ============================================================
-- 第六部分：示例数据（表为空时才插入）
-- ============================================================
insert into products (name, zone, price, description, story, kind)
select * from (values
  ('旧木板床头置物板', 'bed', 25,
   '回收旧木板打磨上漆，挂在床沿存放手机和书。',
   '这张置物板来自毕业生留下的旧木板。社团同学打磨去刺、上环保木蜡油，再装上防滑挂钩，让它重新挂回床沿。', 'diy'),
  ('改造奶茶吸管笔筒', 'desk', 12,
   '收集的奶茶吸管捆扎成笔筒，桌面杂物一件收纳。',
   '喝完的吸管洗净晾干，按颜色捆扎成筒壁，底座用回收硬纸板加固，每个颜色搭配都独一无二。', 'diy'),
  ('旧衣改造地垫', 'floor', 39,
   '回收旧衣物编织的柔软地垫。',
   '毕业季收到的一袋旧 T 恤，剪成布条、三股编织、盘圆缝合，旧衣的柔软留在了宿舍的每个清晨。', 'diy')
) as v(name, zone, price, description, story, kind)
where not exists (select 1 from products);

insert into stock_items (title, category, description, source, cost, status)
select * from (values
  ('二手实木书架（校友捐赠）', '家具', '结构完好，漆面磨损，适合打磨翻新成置物架。', 'offline', 15.00, 'available'),
  ('旧台灯 3 台（跳蚤市场收购）', '电器', '灯罩发黄、线路正常，可改造成氛围小夜灯。', 'offline', 9.00, 'available'),
  ('旧牛仔布窗帘', '织物', '布料厚实，可改造成收纳袋或地垫。', 'offline', 5.00, 'available')
) as v(title, category, description, source, cost, status)
where not exists (select 1 from stock_items);

-- ============================================================
-- 第七部分：账号角色（自动识别 + 兜底）
-- ============================================================
-- 补齐所有账号档案
insert into public.profiles (id, nickname)
select u.id, split_part(u.email, '@', 1)
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null;

-- 邮箱含 admin → 管理员；含 member/club/diy → 社团成员；其余 → 学生
update public.profiles p set role = 'admin'
where p.id in (select id from auth.users where email ilike '%admin%');

update public.profiles p set role = 'member'
where p.id in (select id from auth.users
               where email ilike '%member%' or email ilike '%club%' or email ilike '%diy%');

update public.profiles p set role = 'student'
where p.id in (select u.id from auth.users u
               where u.email not ilike '%admin%' and u.email not ilike '%member%'
                 and u.email not ilike '%club%' and u.email not ilike '%diy%');

-- 查看结果（应看到 admin / member / student）
select u.email as "邮箱", p.role as "角色", p.nickname as "昵称", p.points as "积分"
from public.profiles p
join auth.users u on u.id = p.id
order by p.role;
