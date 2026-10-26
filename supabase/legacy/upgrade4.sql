-- ============================================================
-- 宿舍焕新 v6：家园系统数据底座（转赠关系 + 家园状态）
-- 说明：本轮前端用本地存储演示，本脚本为 P2「真实转赠关系」准备
-- 幂等，可重复运行
-- ============================================================

-- ---------- 1. 转赠记录（平台上二手物品的再次流转） ----------
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
alter table transfers enable row level security;

-- 双方和管理员可见
drop policy if exists "transfers_read" on transfers;
create policy "transfers_read" on transfers for select to authenticated
  using (auth.uid() = from_user or auth.uid() = to_user or public.is_admin());

-- 只能以自己的名义发起转赠
drop policy if exists "transfers_insert" on transfers;
create policy "transfers_insert" on transfers for insert to authenticated
  with check (auth.uid() = from_user);

-- 受赠方可以接受/拒绝
drop policy if exists "transfers_update_receiver" on transfers;
create policy "transfers_update_receiver" on transfers for update to authenticated
  using (auth.uid() = to_user) with check (auth.uid() = to_user);

-- ---------- 2. 家园状态（等级 / 主题 / 亲密度） ----------
create table if not exists home_state (
  user_id    uuid primary key references profiles(id) on delete cascade,
  level      int not null default 0,          -- 由购买件数换算：1 件 Lv1 / 3 件 Lv2 / 5 件 Lv3
  theme      text default 'mint',             -- 当前宿舍风格 key
  intimacy   int not null default 0,          -- 与好友的亲密度
  partner    uuid references profiles(id) on delete set null,  -- 双人家园伙伴
  has_baby   boolean not null default false,  -- 亲密度达标后的彩蛋
  updated_at timestamptz default now()
);
alter table home_state enable row level security;

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

-- ---------- 3. 好友列表视图：与我发生过「已接受转赠」的用户 ----------
create or replace view my_transfer_friends
with (security_invoker = true) as
select t.from_user as me, t.to_user as friend_id, p.nickname, t.product_id, t.created_at
from transfers t
join profiles p on p.id = t.to_user
where t.status = 'accepted'
union
select t.to_user as me, t.from_user as friend_id, p.nickname, t.product_id, t.created_at
from transfers t
join profiles p on p.id = t.from_user
where t.status = 'accepted';

grant select on my_transfer_friends to authenticated;
