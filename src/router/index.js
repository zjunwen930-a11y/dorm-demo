import { createRouter, createWebHistory } from 'vue-router'
import { useAuth } from '../stores/auth'
import { supabase } from '../lib/supabase'

/**
 * 路由表 + 角色守卫
 * 注意：前端守卫只是体验层（防止误入），真正的数据安全由 Supabase RLS 保证
 */
const routes = [
  { path: '/', name: 'home', component: () => import('../views/HomeView.vue') },
  { path: '/shop', name: 'shop', component: () => import('../views/ShopView.vue') },
  { path: '/recycle', name: 'recycle', component: () => import('../views/RecycleView.vue'), meta: { requiresAuth: true } },
  // 社团工作台：member / admin
  { path: '/club', name: 'club', component: () => import('../views/ClubView.vue'), meta: { requiresAuth: true, roles: ['member', 'admin'] } },
  // 管理后台：仅 admin
  { path: '/admin', name: 'admin', component: () => import('../views/AdminView.vue'), meta: { requiresAuth: true, roles: ['admin'] } },
  { path: '/profile', name: 'profile', component: () => import('../views/ProfileView.vue'), meta: { requiresAuth: true } },
  { path: '/login', name: 'login', component: () => import('../views/LoginView.vue') },
  { path: '/:pathMatch(.*)*', redirect: '/' },
]

const router = createRouter({ history: createWebHistory(), routes })

router.beforeEach(async (to) => {
  const { user, role, loading } = useAuth()
  // 等待登录状态初始化完成，避免刷新页面时误判角色
  if (loading.value) await new Promise(r => setTimeout(r, 150))

  if (to.meta.requiresAuth && !user.value) {
    return { name: 'login', query: { redirect: to.fullPath } }
  }
  if (to.meta.roles && !to.meta.roles.includes(role.value)) {
    const names = to.meta.roles.map(r => (r === 'member' ? 'DIY社团成员' : r === 'admin' ? '管理员' : r)).join(' / ')
    alert('权限不足：该页面仅限 ' + names + ' 访问')
    return { name: 'home' }
  }
  return true
})

export { supabase }
export default router
