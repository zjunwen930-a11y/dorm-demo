<script setup>
import { useAuth } from './stores/auth'

const { user, role, nickname, isAdmin, isMember } = useAuth()

const ROLE_TEXT = { student: '学生', member: '社团', admin: '管理员' }
</script>

<template>
  <div class="min-h-screen flex flex-col">
    <!-- 顶部导航：按角色显示不同菜单（真正的数据隔离由数据库 RLS 负责） -->
    <header class="bg-white/90 backdrop-blur sticky top-0 z-40 border-b border-mint-100">
      <nav class="max-w-5xl mx-auto flex items-center gap-1 px-3 py-2.5 overflow-x-auto">
        <router-link to="/" class="font-bold text-mint-600 whitespace-nowrap mr-2">🌿 宿舍焕新</router-link>

        <!-- 所有角色通用 -->
        <router-link to="/" class="nav-link">首页</router-link>
        <router-link to="/shop" class="nav-link">改造商城</router-link>

        <!-- 普通学生：投稿闲置 -->
        <router-link v-if="user && !isAdmin && !isMember" to="/recycle" class="nav-link">闲置投稿</router-link>

        <!-- 社团成员 -->
        <router-link v-if="user && isMember" to="/club" class="nav-link">社团工作台</router-link>

        <!-- 管理员 -->
        <router-link v-if="user && isAdmin" to="/admin" class="nav-link">管理后台</router-link>

        <span class="flex-1"></span>

        <template v-if="user">
          <span class="hidden sm:inline text-xs px-2.5 py-1 rounded-full bg-mint-100 text-mint-700 whitespace-nowrap">
            {{ ROLE_TEXT[role] }} · {{ nickname }}
          </span>
          <router-link to="/profile" class="nav-link">我的</router-link>
        </template>
        <router-link v-else to="/login" class="btn-primary !py-1.5 !px-4 text-sm whitespace-nowrap">登录</router-link>
      </nav>
    </header>

    <main class="flex-1">
      <router-view />
    </main>

    <footer class="text-center text-xs text-gray-400 py-6">
      校园闲置回收 & 改造计划 · 国创赛演示 Demo
    </footer>
  </div>
</template>

<style scoped>
.nav-link {
  @apply px-3 py-1.5 rounded-full text-sm text-gray-600 whitespace-nowrap hover:bg-mint-50 hover:text-mint-600 transition;
}
.router-link-active.nav-link { @apply bg-mint-100 text-mint-700 font-medium; }
</style>
