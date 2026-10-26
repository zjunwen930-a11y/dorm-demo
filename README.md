# 宿舍焕新 · 国创赛演示 Demo

> ## ✅ 数据库只看一个文件：`supabase/setup_all.sql`
> 建表、权限（RLS）、触发器、示例数据、账号角色，**全部合并在这一个文件里**。
> 打开 Supabase → SQL Editor → 新建查询 → 全文粘贴 → Run，跑一次就行（重复跑也不报错）。
> 运行完会自动列出所有账号的角色表格。
>
> `supabase/legacy/` 里是历史版本的零散脚本，**已经全部合并进 setup_all.sql，不要再运行**，仅留作记录。

---

## 📁 项目文件地图（只有这几处要认）

| 位置 | 是什么 | 要不要动 |
|---|---|---|
| `supabase/setup_all.sql` | **唯一数据库脚本**（建表+权限+示例数据+角色） | 只需要在 Supabase 里跑一次 |
| `src/main.js` | 前端启动入口 | 不用动 |
| `src/App.vue` | 顶部导航（按角色显示菜单） | 不用动 |
| `src/views/` | 7 个页面：首页、商城、闲置投稿、社团工作台、管理后台、个人中心、登录 | 改文案可来这里 |
| `src/components/Dorm3D.vue` | 3D 宿舍家园（小人/猫狗/盲盒风格/好友邀请） | 不用动 |
| `src/three/` | Q版小人 `avatar.js`、宠物 `pet.js` | 不用动 |
| `src/lib/supabase.js` + `.env` | 数据库连接配置 | `.env` 里填你的 URL 和 Key |
| `supabase/legacy/` | 历史零散 SQL（已合并，**不要运行**） | 忽略 |

---

这是一个网站项目（手机、电脑都能打开的网页）。
**你不需要看懂代码**，照着下面 3 步做就能把它跑起来、放到网上给评委看。

---

## 第一步：在自己电脑上打开这个网站（约 20 分钟）

### 准备工作（只做一次）

1. **安装 Node.js**
   - 打开网址：https://nodejs.org
   - 点击绿色的下载按钮，下载 "LTS" 版本
   - 双击下载好的文件，一路点「下一步」安装完成

2. **注册一个 Supabase 账号（免费）**
   - Supabase 就是这个网站的「免费云端数据库」，帮我们存用户、商品、投稿
   - 打开网址：https://supabase.com → 点右上角 **Sign up** → 用邮箱注册
   - 注册后点 **New project** 新建一个项目：
     - Name 随便填（比如 `dorm`）
     - 数据库密码它会自动生成，不用记
     - 地区选 **Singapore** 或 **Tokyo**（离国内近，速度快）
   - 等待 1-2 分钟，项目创建完成

### 开始操作

3. **把数据库的表建好**
   - 在 Supabase 网页左侧菜单，找到 **SQL Editor**，点进去
   - 点左上角 **+ New query**
   - 用记事本打开本项目文件夹里的 `supabase/setup_all.sql` 文件，**全选复制**里面的内容
   - 粘贴到 SQL Editor 的输入框里，点右下角绿色 **Run** 按钮
   - 看到 "Success" 就说明数据库建好了（页面底部会列出所有账号的角色表格）

4. **创建 3 个演示账号**（答辩时用来展示三种角色）
   - Supabase 左侧菜单 → **Authentication** → **Users** → 点 **Add user** → **Create new user**
   - 创建 3 次，分别用 3 个邮箱，比如：
     - `stu@test.com`（普通学生）
     - `member@test.com`（DIY社团成员）
     - `admin@test.com`（管理员）
     - 密码自己定（比如 `123456`），勾选 Auto Confirm User
   - 角色不用手动改：跑完 setup_all.sql 会**按邮箱自动分配**（含 admin 的是管理员，含 member/club/diy 的是社团成员，其余是学生）

5. **把 Supabase 的「钥匙」填进项目**
   - Supabase 左侧菜单 → 点齿轮 **Project Settings** → **API** 或 **Data API**
   - 复制两样东西：
     - **Project URL**（形如 `https://xxxxx.supabase.co`，注意**结尾就是域名，不带任何斜杠和路径**）
     - **Publishable key**（`sb_publishable_` 开头的一串字符）
   - 打开项目里的 `.env` 文件（已建好），改成：
     ```
     VITE_SUPABASE_URL=https://xxxxx.supabase.co
     VITE_SUPABASE_ANON_KEY=sb_publishable_xxxxxxxx
     ```
   - 保存关闭

6. **启动网站**
   - 在 `dorm-demo` 文件夹里，按住 Shift 点右键 →「在此处打开 PowerShell 窗口」（Win11：在终端中打开）
   - 依次输入（第一次要几分钟）：
     ```
     npm install
     npm run dev
     ```
   - 看到 `Local: http://localhost:5173` 后，按住 Ctrl 点击链接即可打开

> 小提示：浏览器按 F12 → 点左上角手机图标，可切换手机视口看移动端效果。

---

## 第二步：部署到网上（约 10 分钟）

1. **GitHub Desktop 上传代码**
   - https://desktop.github.com 下载安装，登录 GitHub 账号
   - 左上角 File → **Add local repository** → 选择 `dorm-demo` 文件夹（按提示 create 仓库）
   - ⚠️ **注意：创建仓库时不要勾选 "Initialize this repository with a README"**（上次就是勾了它，把项目说明书覆盖了）
   - 填 Summary（如"第一次上传"）→ **Commit to main** → **Publish repository**

2. **Vercel 一键上线**
   - https://vercel.com → Sign up → **Continue with GitHub**
   - **Add New → Project** → 导入 `dorm-demo` 仓库 → **Import**
   - 在 **Environment Variables** 添加两条：
     - `VITE_SUPABASE_URL` = 你的 Project URL
     - `VITE_SUPABASE_ANON_KEY` = 你的 Publishable key
   - 点 **Deploy**，约 1 分钟得到线上网址，发微信即可扫码访问

---

## 常见问题

| 问题 | 解决办法 |
|---|---|
| `npm run dev` 报错 Could not read package.json | 你在外层文件夹里了，先输入 `cd dorm-demo` 再运行 |
| 登录报 Invalid path specified | `.env` 里 URL 写多了路径，结尾必须是 `.supabase.co`，后面什么都不要 |
| 管理员/社团登录没有专属界面 | 数据库角色没写入：重新运行 `supabase/setup_all.sql`，看底部角色表格；确认邮箱里含 admin / member 关键词 |
| Vercel 上刷新 404 | 项目根目录加 `vercel.json`：`{"rewrites":[{"source":"/(.*)","destination":"/index.html"}]}` 后重新部署 |
| 忘记 URL / Key | Supabase → Settings → API 随时可看 |

---

## 角色与权限（答辩要点）

| 角色 | 界面 | 能力 |
|---|---|---|
| 普通学生 | 首页 / 改造商城 / 闲置投稿 / 我的 | 看两类商品（✨翻新二手 + 🎨社团改造）、投稿闲置、提交购买意向 |
| DIY社团成员 | 首页 / 改造商城 / 社团工作台 | 只能看到管理员开放认领的旧货池 → 申请认领 → 改造后上架成品 |
| 管理员 | 首页 / 改造商城 / 管理后台 | 审核旧货（翻新后直接上架 或 开放给社团认领）、线下进货、发货、成品上下架、分配角色 |

**后端鉴权核心**：角色存 `profiles.role`，全部表开启 RLS；辅助函数 `my_role()` / `is_admin()` 在数据库端校验，伪造请求直接被拒绝。

## 完整演示动线（答辩照这个顺序演）

1. 学生登录 → 闲置投稿（传 2 张图）→「我的」看到审核中
2. 管理员登录 → 管理后台「旧货池」→ 点「开放给社团认领」
3. 社团登录 → 工作台「旧货池」看到物品 → 申请认领（写改造思路）
4. 管理员 →「认领申请」→ 通过并发货
5. 社团 →「我的认领」→ 改造完成，上架成品（价格/故事/过程图）
6. 学生 → 改造商城看到成品 → 提交购买意向（🎁 解锁宿舍盲盒）
7. 管理员 →「购买意向」标记已联系

另一条线：管理员在旧货池点「翻新后上架」，学生立即能买到「✨翻新二手」。

## 功能亮点清单

- 🔥 **改造物品热门趋势榜**：按 购买意向×3 + 收藏×1 排序，🥇🥈🥉
- 📸 **三步过程图**：回收筛选 → 翻新/改造 → 焕新上架（商品详情弹窗时间轴）
- 💚 **碳积分**：投稿 +10 / 购买 +5，数据库触发器自动加，等级徽章 + 排行榜
- 🏠 **3D 宿舍家园**：Q版小人自己看书/画画/玩电脑/睡觉；猫狗巡逻睡觉；房间精修（地板缝/踢脚线/挂钟/吊灯/书桌椅）
- 🎁 **盲盒风格**：6 套主题（薄荷/暖阳/樱粉/夜蓝霓虹/森野/复古），买一单开一次箱，粒子特效 + 相机环绕
- 🏆 **家园成长**：买 1/3/5 件分别解锁落地灯 / 沙发挂画 / 吊灯抱枕
- 🤝 **双人家园**：邀请转赠伙伴来家里玩，亲密度满 100 解锁「小屋新成员」彩蛋
- 🔒 **后端鉴权**：三角色数据严格隔离，伪造请求在数据库端被拒绝

## 3D 盲盒 6 套风格

| 风格 | 变化 |
|---|---|
| 薄荷清新 🌿 | 原木 + 圆地毯 + 绿植 + 笔记本 |
| 暖阳米杏 ☀️ | 米杏墙 + 方地毯 + 窗帘 + 纸灯笼 + 马克杯 |
| 樱粉少女 🌸 | 粉墙 + 星星灯串 + 花边窗帘 + 三盆绿植 |
| 夜蓝霓虹 🌙 | 整屋变暗 + 紫青霓虹灯带 + 灯串 |
| 森野绿意 🍃 | 深木色 + 5 盆绿植 + 纸灯笼 |
| 复古木质 🪵 | 深棕木纹 + 红棕方格地毯 + 3 张海报 + 旧书堆 |

---

*本项目为国创赛演示 Demo，商城仅支持「提交购买意向」，不含真实支付。*
