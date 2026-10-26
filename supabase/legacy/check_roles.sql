-- ============================================================
-- 角色一键修复脚本（自动识别版，不需要改任何邮箱）
-- 用法：Supabase → SQL Editor → 全选粘贴 → Run → 看最后一张表格
--
-- 识别规则（按你注册邮箱的名字）：
--   邮箱里含 admin  → 管理员
--   邮箱里含 member / club / diy → DIY社团成员
--   其他（stu / student / 其他）  → 普通学生
-- ============================================================

-- 1) 补齐所有账号的档案（缺档案 = 前端读不到角色 = 三种角色界面一样）
insert into public.profiles (id, nickname)
select u.id, split_part(u.email, '@', 1)
from auth.users u
left join public.profiles p on p.id = u.id
where p.id is null;

-- 2) 自动分配角色
update public.profiles p set role = 'admin'
where p.id in (select id from auth.users where email ilike '%admin%');

update public.profiles p set role = 'member'
where p.id in (select id from auth.users where email ilike '%member%' or email ilike '%club%' or email ilike '%diy%');

update public.profiles p set role = 'student'
where p.id in (
  select u.id from auth.users u
  where u.email not ilike '%admin%' and u.email not ilike '%member%'
    and u.email not ilike '%club%' and u.email not ilike '%diy%'
);

-- 3) 查看结果：这张表格里应该能看到 admin / member / student
select u.email as "邮箱", p.role as "角色", p.nickname as "昵称"
from public.profiles p
join auth.users u on u.id = p.id
order by p.role;

-- ------------------------------------------------------------
-- 如果你的邮箱完全不含这些关键词（比如 123@qq.com），用下面这句手动指定：
-- 把 '你的管理员邮箱' 换成真实邮箱后，去掉前面的 -- 再运行
-- update public.profiles set role='admin' where id=(select id from auth.users where email='你的管理员邮箱');
-- update public.profiles set role='member' where id=(select id from auth.users where email='你的社团邮箱');
-- ------------------------------------------------------------
