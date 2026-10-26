import { ref, computed } from 'vue'
import { supabase } from '../lib/supabase'

/**
 * 全局认证状态（composable 单例）
 * role 来自数据库 profiles 表：student / member / admin
 * 关键修复：若档案缺失则自动补建，避免「所有角色界面都一样」
 */
const user = ref(null)
const role = ref(null) // 'student' | 'member' | 'admin'
const nickname = ref('')
const points = ref(0)
const loading = ref(true)

async function fetchRole() {
  if (!user.value) return
  const { data } = await supabase
    .from('profiles')
    .select('role, nickname, points')
    .eq('id', user.value.id)
    .maybeSingle()

  if (!data) {
    // 档案缺失 → 自动补建（RLS 允许用户插入自己的档案）
    await supabase.from('profiles').insert({
      id: user.value.id,
      nickname: user.value.email?.split('@')[0] ?? '同学',
    })
    role.value = 'student'
    nickname.value = user.value.email?.split('@')[0] ?? '同学'
    return
  }
  role.value = data.role ?? 'student'
  nickname.value = data.nickname || user.value.email?.split('@')[0] || '同学'
  points.value = data.points ?? 0
}

supabase.auth.getSession().then(async ({ data }) => {
  user.value = data.session?.user ?? null
  if (user.value) await fetchRole()
  loading.value = false
})

supabase.auth.onAuthStateChange(async (event, session) => {
  user.value = session?.user ?? null
  role.value = null
  if (user.value) await fetchRole()
  // 登录后按角色跳转到对应首页（学生→商城，社团→工作台，管理员→后台）
  if (event === 'SIGNED_IN' && session?.user && location.pathname === '/login') {
    const { data } = await supabase.from('profiles').select('role').eq('id', session.user.id).maybeSingle()
    const r = data?.role ?? 'student'
    location.href = r === 'admin' ? '/admin' : r === 'member' ? '/club' : '/'
  }
})

const isAdmin = computed(() => role.value === 'admin')
const isMember = computed(() => role.value === 'member')
const isStudent = computed(() => role.value === 'student')

async function signIn(email, password) {
  const { error } = await supabase.auth.signInWithPassword({ email, password })
  if (error) throw error
}

async function signOut() {
  await supabase.auth.signOut()
}

export function useAuth() {
  return { user, role, nickname, points, loading, isAdmin, isMember, isStudent, signIn, signOut }
}
