-- ============================================================
-- 宿舍焕新 v4：热门趋势榜 + 三步过程图 + 盲盒主题
-- 前置：请先成功运行 upgrade2.sql（旧货池 + 认领 + 商品类型）
-- 本脚本幂等，可重复运行。运行前关闭浏览器翻译。
-- ============================================================

-- ---------- 0. 再次回填缺失的用户档案（角色看不到后台的根因） ----------
insert into public.profiles (id, nickname)
select u.id, split_part(u.email, '@', 1)
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null;

-- ---------- 1. 商品增加「过程图」字段 ----------
-- 三步过程：回收筛选(before) → 翻新/改造中(process) → 成品(after)
alter table products add column if not exists process_images jsonb default '[]'::jsonb;

-- ---------- 2. 热门趋势榜：按 购买意向×3 + 收藏×1 计算热度 ----------
-- 用 security definer 函数只暴露聚合数字，不泄露他人订单明细
create or replace function public.hot_products()
returns table (product_id uuid, order_count bigint, fav_count bigint, hot_score bigint)
language sql security definer set search_path = public stable as $$
  select
    p.id,
    coalesce(o.cnt, 0)::bigint as order_count,
    coalesce(f.cnt, 0)::bigint as fav_count,
    (coalesce(o.cnt, 0) * 3 + coalesce(f.cnt, 0))::bigint as hot_score
  from products p
  left join (select product_id, count(*) cnt from orders group by product_id) o on o.product_id = p.id
  left join (select product_id, count(*) cnt from favorites group by product_id) f on f.product_id = p.id
  where p.status = 'online';
$$;

grant execute on function public.hot_products() to anon, authenticated;

-- ---------- 3. 演示数据：给已有商品补上三步过程图（用占位图，可换成自己的照片 URL） ----------
update products
set process_images = to_jsonb(array['https://images.unsplash.com/photo-1616627561950-9f746e330187?w=800'])
where (process_images is null or process_images = '[]'::jsonb);

-- ---------- 4. 自检查询：运行完可执行下面这句，确认 3 个账号角色是否正确 ----------
-- select p.role, p.nickname, u.email from public.profiles p join auth.users u on u.id = p.id order by p.role;
