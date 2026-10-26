<script setup>
/**
 * 闲置回收投稿页 —— 多图上传 + 表单
 * 登录用户（任何角色）均可投稿；图片存 Supabase Storage 的 recycle-images bucket。
 */
import { ref } from 'vue'
import { supabase } from '../lib/supabase'
import { useAuth } from '../stores/auth'

const { user } = useAuth()

const form = ref({ title: '', category: '家具', description: '' })
const files = ref([])        // 选中的本地文件
const previews = ref([])     // 本地预览 base64
const uploading = ref(false)
const message = ref('')

const MAX_IMAGES = 6 // 最多 6 张

function onPick(e) {
  const list = Array.from(e.target.files).slice(0, MAX_IMAGES - files.value.length)
  list.forEach(f => {
    files.value.push(f)
    const reader = new FileReader()
    reader.onload = ev => previews.value.push(ev.target.result)
    reader.readAsDataURL(f)
  })
  e.target.value = '' // 允许重复选择同一文件
}

function removeImg(i) {
  files.value.splice(i, 1)
  previews.value.splice(i, 1)
}

async function submit() {
  if (!form.value.title) { message.value = '请填写物品名称'; return }
  uploading.value = true
  message.value = ''
  try {
    // 1. 逐张上传图片到 Storage，收集公开 URL
    const urls = []
    for (const f of files.value) {
      const path = `${user.value.id}/${Date.now()}-${Math.random().toString(36).slice(2)}.${f.name.split('.').pop()}`
      const { error: upErr } = await supabase.storage
        .from('recycle-images').upload(path, f)
      if (upErr) throw upErr
      urls.push(supabase.storage.from('recycle-images').getPublicUrl(path).data.publicUrl)
    }
    // 2. 写入投稿记录（RLS 会校验：必须是自己且已登录）
    const { error } = await supabase.from('recycle_posts').insert({
      author: user.value.id,
      title: form.value.title,
      category: form.value.category,
      description: form.value.description,
      images: urls,
    })
    if (error) throw error
    message.value = '投稿成功！等待管理员审核上架 ✓'
    form.value = { title: '', category: '家具', description: '' }
    files.value = []; previews.value = []
  } catch (err) {
    message.value = '投稿失败：' + (err.message || err.errorDescription || '未知错误')
  } finally {
    uploading.value = false
  }
}
</script>

<template>
  <div class="max-w-xl mx-auto px-4 py-8">
    <h1 class="text-xl font-bold text-mint-700 mb-1">♻️ 闲置回收投稿</h1>
    <p class="text-sm text-gray-500 mb-6">拍下你想处理的闲置物品。投稿后会由管理员审核：可翻新后直接上架，也可交给 DIY 社团认领改造。</p>

    <form class="card space-y-4" @submit.prevent="submit">
      <div>
        <label class="text-sm text-gray-600">物品名称 *</label>
        <input v-model="form.title" class="input" placeholder="例如：旧木椅" />
      </div>
      <div>
        <label class="text-sm text-gray-600">分类</label>
        <select v-model="form.category" class="input">
          <option>家具</option><option>电器</option><option>织物</option><option>书籍</option><option>其他</option>
        </select>
      </div>
      <div>
        <label class="text-sm text-gray-600">物品描述</label>
        <textarea v-model="form.description" rows="3" class="input" placeholder="尺寸、成色、想改造的方向…" />
      </div>

      <!-- 多图上传 -->
      <div>
        <label class="text-sm text-gray-600">图片（最多 {{ MAX_IMAGES }} 张）</label>
        <label class="mt-1 flex flex-col items-center justify-center gap-1 border-2 border-dashed border-mint-300 rounded-2xl py-6 cursor-pointer hover:bg-mint-50 transition">
          <span class="text-2xl">📷</span>
          <span class="text-xs text-gray-400">点击拍照或选择图片</span>
          <input type="file" accept="image/*" multiple class="hidden" @change="onPick" />
        </label>
        <!-- 预览与删除 -->
        <div v-if="previews.length" class="flex flex-wrap gap-2 mt-3">
          <div v-for="(p, i) in previews" :key="i" class="relative">
            <img :src="p" class="w-16 h-16 object-cover rounded-lg" />
            <button type="button" class="absolute -top-1.5 -right-1.5 w-5 h-5 bg-red-400 text-white rounded-full text-xs"
              @click="removeImg(i)">✕</button>
          </div>
        </div>
      </div>

      <p v-if="message" class="text-sm rounded-xl px-4 py-2"
        :class="message.includes('成功') ? 'bg-mint-100 text-mint-700' : 'bg-red-50 text-red-500'">{{ message }}</p>

      <button type="submit" :disabled="uploading" class="btn-primary w-full disabled:opacity-50">
        {{ uploading ? '上传中…' : '提交投稿' }}
      </button>
    </form>
  </div>
</template>

<style scoped>
.input { @apply w-full mt-1 border border-gray-200 rounded-xl px-3 py-2.5 text-sm focus:outline-none focus:ring-2 focus:ring-mint-300 bg-white; }
</style>
