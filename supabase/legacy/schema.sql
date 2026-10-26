-- ============================================================
-- 宿舍焕新 Demo —— Supabase 建表 SQL 与 RLS 权限策略
-- 在 Supabase Dashboard → SQL Editor 中整体执行一次即可
-- ============================================================

-- ---------- 0. 用户角色枚举 ----------
create type app_role as enum ('student', 'member', 'admin');

-- ---------- 1. profiles：用户档案（角色存放处） ----------
-- 注册时由触发器自动创建一行，默认 student
create table profiles (
  id          uuid primary key references auth.users(id) on delete cascade,
  nickname    text,
  role        app_role not null default 'student',
  created_at  timestamptz default now()
);

-- 新用户注册 → 自动建档
create function public.handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  insert into public.profiles (id, nickname)
  values (new.id, coalesce(new.raw_user_meta_data->>'nickname', split_part(new.email, '@', 1)));
  return new;
end $$;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function public.handle_new_user();

-- ---------- 角色判断辅助函数（RLS 策略中调用，性能好且防伪造） ----------
create function public.my_role() returns app_role
language sql security definer set search_path = public stable as $$
  select role from public.profiles where id = auth.uid();
$$;

create function public.is_admin() returns boolean
language sql security definer set search_path = public stable as $$
  select public.my_role() = 'admin';
$$;

create function public.is_member_or_admin() returns boolean
language sql security definer set search_path = public stable as $$
  select public.my_role() in ('member', 'admin');
$$;

-- ---------- 2. recycle_posts：闲置回收投稿 ----------
create table recycle_posts (
  id          uuid primary key default gen_random_uuid(),
  author      uuid not null references profiles(id) on delete cascade,
  title       text not null,
  category    text default '其他',
  description text,
  images      jsonb default '[]'::jsonb,   -- 图片 URL 数组（多图上传）
  status      text default 'pending',      -- pending 待认领 / claimed 改造中 / done 已完成
  created_at  timestamptz default now()
);

-- ---------- 3. products：改造商城商品 ----------
create table products (
  id           uuid primary key default gen_random_uuid(),
  name         text not null,
  zone         text not null default 'floor', -- bed/desk/nightstand/shelf/floor（对应3D热区）
  price        numeric(10,2) not null default 0,
  description  text,
  image_before text,
  image_after  text,
  source_post  uuid references recycle_posts(id) on delete set null, -- 改造来源投稿
  created_at   timestamptz default now()
);

-- ---------- 4. orders：购买意向（无真实支付） ----------
create table orders (
  id         uuid primary key default gen_random_uuid(),
  product_id uuid not null references products(id) on delete cascade,
  buyer      uuid not null references profiles(id) on delete cascade,
  status     text default 'new',             -- new 新意向 / contacted 已联系
  created_at timestamptz default now(),
  unique (product_id, buyer)                 -- 同一用户同一商品只提交一次
);

-- ============================================================
-- 开启 RLS（行级安全）—— 所有越权请求在数据库端直接拒绝
-- ============================================================
alter table profiles      enable row level security;
alter table recycle_posts enable row level security;
alter table products      enable row level security;
alter table orders        enable row level security;

-- ---------- profiles 策略 ----------
-- 所有人可读（首页展示需要）；本人可改自己的昵称；只有 admin 可改任何人的角色
create policy "profiles_read" on profiles for select using (true);
create policy "profiles_update_self" on profiles for update
  using (auth.uid() = id) with check (auth.uid() = id and role = public.my_role());
create policy "profiles_update_role_admin" on profiles for update
  using (public.is_admin()) with check (public.is_admin());

-- ---------- recycle_posts 策略 ----------
-- 所有登录用户可读（社团展示）；登录用户可创建自己的投稿；只能改/删自己的
create policy "posts_read_auth" on recycle_posts for select to authenticated using (true);
create policy "posts_insert_own" on recycle_posts for insert to authenticated
  with check (auth.uid() = author);
create policy "posts_update_own" on recycle_posts for update to authenticated
  using (auth.uid() = author or public.is_member_or_admin())
  with check (auth.uid() = author or public.is_member_or_admin());
create policy "posts_delete_own" on recycle_posts for delete to authenticated
  using (auth.uid() = author or public.is_admin());

-- ---------- products 策略 ----------
-- 任何用户（含未登录访客）可读；只有 member/admin 可上架和修改
create policy "products_read_all" on products for select using (true);
create policy "products_write_member" on products for insert to authenticated
  with check (public.is_member_or_admin());
create policy "products_update_member" on products for update to authenticated
  using (public.is_member_or_admin()) with check (public.is_member_or_admin());
create policy "products_delete_admin" on products for delete to authenticated
  using (public.is_admin());

-- ---------- orders 策略 ----------
-- 社团/管理员可读全部；普通登录用户只能看到自己的；只能为自己的购买意向下单
create policy "orders_read" on orders for select to authenticated
  using (auth.uid() = buyer or public.is_member_or_admin());
create policy "orders_insert_own" on orders for insert to authenticated
  with check (auth.uid() = buyer);
create policy "orders_update_staff" on orders for update to authenticated
  using (public.is_member_or_admin()) with check (public.is_member_or_admin());

-- ============================================================
-- Storage：投稿多图上传桶（公开读取，仅登录者可上传自己目录下的文件）
-- ============================================================
insert into storage.buckets (id, name, public) values ('recycle-images', 'recycle-images', true)
on conflict (id) do nothing;

create policy "storage_read_public" on storage.objects for select
  using (bucket_id = 'recycle-images');
create policy "storage_upload_auth" on storage.objects for insert to authenticated
  with check (bucket_id = 'recycle-images' and (storage.foldername(name))[1] = auth.uid()::text);
create policy "storage_delete_own" on storage.objects for delete to authenticated
  using (bucket_id = 'recycle-images' and (storage.foldername(name))[1] = auth.uid()::text);

-- ============================================================
-- 演示种子数据：3 个分区示例商品（bed / desk / floor）
-- ============================================================
insert into products (name, zone, price, description) values
  ('旧木板床头置物板', 'bed', 25, '回收旧木板打磨上漆，挂在床沿存放手机和书，告别床上杂物堆积。'),
  ('改造奶茶吸管笔筒', 'desk', 12, '收集的奶茶吸管捆扎成笔筒，桌面杂物一件收纳。'),
  ('旧衣改造地垫', 'floor', 39, '回收旧衣物编织的柔软地垫，铺在宿舍地面收纳区旁，脚感舒适。');


-- 若之前执行失败过一次，先在 SQL Editor 里单独运行下面这几行清理，再整体运行整个文件：
-- drop table if exists orders, products, recycle_posts, profiles cascade;
-- drop function if exists public.handle_new_user, public.my_role, public.is_admin, public.is_member_or_admin cascade;
-- drop type if exists app_role;
