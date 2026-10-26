-- ============================================================
-- 宿舍焕新 v2 功能升级脚本（幂等：重复运行不会报错）
-- 适合已经运行过旧版 schema.sql 的项目；新项目直接运行 schema.sql 即可
-- ============================================================

-- ---------- 1. 商品新增「改造故事」字段 ----------
alter table products add column if not exists story text;

-- ---------- 2. 用户碳积分 ----------
alter table profiles add column if not exists points int not null default 0;

-- 积分触发器：投稿 +10，提交购买意向 +5（数据库端自动执行，前端无法伪造）
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

-- ---------- 3. 收藏夹 ----------
create table if not exists favorites (
  user_id    uuid not null references profiles(id) on delete cascade,
  product_id uuid not null references products(id) on delete cascade,
  created_at timestamptz default now(),
  primary key (user_id, product_id)
);
alter table favorites enable row level security;
drop policy if exists "fav_own_all" on favorites;
create policy "fav_own_all" on favorites for all to authenticated
  using (auth.uid() = user_id) with check (auth.uid() = user_id);

-- ---------- 4. 闲置广场：求领养留言 ----------
create table if not exists post_requests (
  id         uuid primary key default gen_random_uuid(),
  post_id    uuid not null references recycle_posts(id) on delete cascade,
  requester  uuid not null references profiles(id) on delete cascade,
  message    text default '',
  status     text default 'new',              -- new 未处理 / contacted 已联系
  created_at timestamptz default now(),
  unique (post_id, requester)                 -- 同一用户对同一闲置只留言一次
);
alter table post_requests enable row level security;
-- 留言者本人和社团/管理员可见；只能以自己的名义留言
drop policy if exists "pr_read" on post_requests;
create policy "pr_read" on post_requests for select to authenticated
  using (auth.uid() = requester or public.is_member_or_admin());
drop policy if exists "pr_insert" on post_requests;
create policy "pr_insert" on post_requests for insert to authenticated
  with check (auth.uid() = requester);
drop policy if exists "pr_update" on post_requests;
create policy "pr_update" on post_requests for update to authenticated
  using (public.is_member_or_admin()) with check (public.is_member_or_admin());

-- ---------- 5. 给演示商品补上改造故事 ----------
update products set story = '这张床头置物板来自毕业生留下的旧木板。社团同学打磨去刺、上环保木蜡油，再装上防滑挂钩，让它重新挂回床沿——手机、眼镜、睡前读物都有了归宿。' where zone = 'bed' and (story is null or story = '');
update products set story = '喝完的奶茶吸管洗净晾干后，按颜色捆扎成筒壁，底座用回收硬纸板加固。每个笔筒的颜色搭配都独一无二，像一份小小的盲盒。' where zone = 'desk' and (story is null or story = '');
update products set story = '临近毕业季，社团收到了一大袋旧 T 恤。我们把它们剪成布条、三股编织、盘成圆形缝合，旧衣的柔软留在了地垫里，也留在了宿舍的每个清晨。' where zone = 'floor' and (story is null or story = '');
