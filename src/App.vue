<script setup>
import { supabaseConfigured } from './lib/supabase'
import { useAuth } from './stores/auth'
const { user, role, nickname, isAdmin, isMember } = useAuth()
const ROLE_TEXT = { student: '学生', member: '社团', admin: '管理员' }
</script>

<template>
  <div class="min-h-screen flex flex-col">
    <a href="#main-content" class="skip-link">跳至正文</a>
    <header class="site-header">
      <nav class="page-shell nav-shell" aria-label="主导航">
        <router-link to="/" class="brand" aria-label="宿舍焕新首页">
          <span class="brand-mark" aria-hidden="true">↗</span>
          <span>宿舍焕新<small>DORM / RENEW</small></span>
        </router-link>
        <div class="nav-items">
          <router-link to="/" class="nav-link">首页</router-link>
          <router-link to="/shop" class="nav-link">改造商城</router-link>
          <router-link v-if="user && !isAdmin && !isMember" to="/recycle" class="nav-link">闲置投稿</router-link>
          <router-link v-if="user && isMember" to="/club" class="nav-link">社团工作台</router-link>
          <router-link v-if="user && isAdmin" to="/admin" class="nav-link">管理后台</router-link>
        </div>
        <div class="nav-account">
          <template v-if="user">
            <span class="hidden lg:inline text-xs text-gray-500">{{ ROLE_TEXT[role] }} · {{ nickname }}</span>
            <router-link to="/profile" class="nav-link">我的</router-link>
          </template>
          <router-link v-else to="/login" class="btn-primary !py-2 !px-4">登录 <span aria-hidden="true">↗</span></router-link>
        </div>
      </nav>
    </header>
    <p v-if="!supabaseConfigured" role="status" class="page-shell w-full py-4 text-sm text-mint-700">当前可预览界面和 3D 家园；本站的数据服务尚未连接，商品、登录及保存功能暂不可用。</p>
    <main id="main-content" class="flex-1" tabindex="-1"><router-view /></main>
    <footer class="site-footer">
      <div class="page-shell flex flex-wrap justify-between gap-4">
        <p><strong>宿舍焕新</strong><span class="ml-3">让好物，继续被喜欢。</span></p>
        <p>校园循环计划 <span class="mx-2">/</span> 演示项目 · 无真实支付</p>
      </div>
    </footer>
  </div>
</template>

<style scoped>
.site-header { position: sticky; top: 0; z-index: 40; background: #f6f5f0f2; backdrop-filter: blur(14px); border-bottom: 1px solid #dce2d8; }
.nav-shell { display: flex; align-items: center; gap: 36px; min-height: 84px; }
.brand { display: flex; gap: 10px; align-items: center; font-weight: 700; font-size: 18px; white-space: nowrap; letter-spacing: .05em; }
.brand small { display: block; font-size: 9px; font-weight: 500; letter-spacing: .18em; color: #7b897d; margin-top: 3px; }
.brand-mark { display: grid; place-items: center; width: 38px; height: 42px; border-radius: 18px 18px 5px 5px; background: #284f40; color: #f0e9d4; font-size: 29px; font-weight: 400; }
.nav-items { display: flex; align-items: center; gap: 8px; }
.nav-link { display: inline-block; padding: 10px 12px; font-size: 13px; color: #68776c; white-space: nowrap; border-bottom: 2px solid transparent; }
.nav-link:hover, .router-link-exact-active.nav-link { color: #284f40; border-bottom-color: #284f40; }
.nav-account { margin-left: auto; display: flex; align-items: center; gap: 12px; }
.site-footer { border-top: 1px solid #dce2d8; padding: 28px 0; margin-top: 64px; font-size: 11px; color: #7b897d; }
.site-footer strong { color: #284f40; font-size: 13px; }
.skip-link { position: fixed; left: 16px; top: -80px; z-index: 100; padding: 10px; background: white; }
.skip-link:focus { top: 10px; }
@media(max-width: 640px) {
  .nav-shell { gap: 14px; min-height: 72px; flex-wrap: wrap; padding-top: 14px; }
  .brand { font-size: 16px; }
  .nav-items { order: 3; width: 100%; overflow-x: auto; gap: 4px; }
  .nav-link { padding: 10px; }
}
</style>
