<script setup>
/**
 * 登录页 —— 演示用邮箱密码登录
 * Supabase Auth 验证身份；角色由 profiles 表决定（管理员在后台分配）。
 */
import { ref } from 'vue'
import { useAuth } from '../stores/auth'
import { useRouter, useRoute } from 'vue-router'

const { signIn } = useAuth()
const router = useRouter()
const route = useRoute()

const email = ref('')
const password = ref('')
const error = ref('')
const busy = ref(false)

async function submit() {
  busy.value = true; error.value = ''
  try {
    await signIn(email.value, password.value)
    router.push(route.query.redirect ?? '/')
  } catch (e) {
    error.value = '登录失败：' + (e.message === 'Invalid login credentials' ? '邮箱或密码错误' : e.message)
  } finally { busy.value = false }
}
</script>

<template>
  <div class="max-w-sm mx-auto px-4 py-16">
    <div class="card space-y-4">
      <h1 class="text-lg font-bold text-mint-700 text-center">🌿 登录 · 宿舍焕新</h1>
      <input v-model="email" type="email" placeholder="邮箱" class="w-full border rounded-xl px-3 py-2.5 text-sm" />
      <input v-model="password" type="password" placeholder="密码" class="w-full border rounded-xl px-3 py-2.5 text-sm" />
      <p v-if="error" class="text-sm text-red-500">{{ error }}</p>
      <button class="btn-primary w-full" :disabled="busy" @click="submit">{{ busy ? '登录中…' : '登录' }}</button>
      <p class="text-xs text-gray-400 text-center">演示账号请联系管理员在后台创建并分配角色</p>
    </div>
  </div>
</template>
