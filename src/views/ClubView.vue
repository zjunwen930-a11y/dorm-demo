<script setup>
/**
 * 社团工作台 v3 —— 仅 DIY 社团成员（member）
 * 看到的只有「管理员审核通过的旧货池」，看不到待审物品（RLS 保证）
 *
 * 流程：申请认领 → 管理员通过并发货 → 线下收货改造 → 上架成品（学生可见）
 */
import { ref, onMounted } from 'vue'
import { supabase } from '../lib/supabase'
import { useAuth } from '../stores/auth'

const { user } = useAuth()
const tab = ref('pool')
const pool = ref([])          // 可认领旧货（status=available）
const myClaims = ref([])      // 我的认领
const myProducts = ref([])    // 我上架的成品
const message = ref('')

// 认领留言弹窗
const claimTarget = ref(null)
const claimNote = ref('')

// 成品上架弹窗
const publishTarget = ref(null)   // 来源认领记录
const form = ref({ name: '', zone: 'bed', price: 0, description: '', story: '', image_after: '', process: '' })

const CLAIM_STATUS = { new: '待管理员审核', accepted: '已通过', delivered: '已发货·可改造', done: '已上架成品' }

async function load() {
  const [p, c, pr] = await Promise.all([
    supabase.from('stock_items').select('*').eq('status', 'available').order('created_at', { ascending: false }),
    // 我的认领：联表取旧货信息
    supabase.from('claims').select('*, stock_items(*)').eq('member', user.value.id).order('created_at', { ascending: false }),
    supabase.from('products').select('*').eq('creator', user.value.id).order('created_at', { ascending: false }),
  ])
  pool.value = p.data ?? []
  myClaims.value = c.data ?? []
  myProducts.value = pr.data ?? []
}
onMounted(load)

/** 申请认领旧货 */
async function submitClaim() {
  const { error } = await supabase.from('claims').insert({
    stock_id: claimTarget.value.id,
    member: user.value.id,
    note: claimNote.value.trim() || '我有改造思路，希望认领这件旧货。',
  })
  message.value = error
    ? (error.code === '23505' ? '你已经申请过这件旧货了' : '申请失败：' + error.message)
    : '认领申请已提交 ✓ 等待管理员审核发货'
  if (!error) claimTarget.value = null
  claimNote.value = ''
  load()
}

/** 打开上架成品弹窗（从已发货的认领进入） */
function openPublish(c) {
  publishTarget.value = c
  form.value = {
    name: c.stock_items?.title ? `改造 · ${c.stock_items.title}` : '',
    zone: 'floor',
    price: 29,
    description: '',
    story: '',
    image_after: '',
    process: '',
  }
}

/** 上架成品：写入 products，同时把旧货标记为已改造、认领标记完成 */
async function publishProduct() {
  const c = publishTarget.value
  const { error } = await supabase.from('products').insert({
    name: form.value.name,
    zone: form.value.zone,
    price: Number(form.value.price) || 0,
    description: form.value.description,
    story: form.value.story,
    image_after: form.value.image_after || null,
    image_before: c.stock_items?.images?.[0] ?? null,  // 改造前照片直接用旧货照片
    process_images: form.value.process ? [form.value.process] : [],
    stock_id: c.stock_id,
    creator: user.value.id,
    status: 'online',
  })
  if (error) { message.value = '上架失败：' + error.message; return }

  // 更新旧货状态 + 认领状态（RLS 允许社团把 assigned → converted）
  await supabase.from('stock_items').update({ status: 'converted' }).eq('id', c.stock_id)
  await supabase.from('claims').update({ status: 'done' }).eq('id', c.id)
  message.value = '成品已上架 ✓ 学生现在可以在改造商城看到它了'
  publishTarget.value = null
  load()
}
</script>

<template>
  <div class="max-w-4xl mx-auto px-4 py-8">
    <h1 class="text-xl font-bold text-mint-700 mb-1">🛠️ 社团工作台</h1>
    <p class="text-xs text-gray-400 mb-4">认领旧货 → 线下改造 → 上架成品</p>

    <p v-if="message" class="text-sm bg-mint-100 text-mint-700 rounded-xl px-4 py-2.5 mb-4">{{ message }}</p>

    <div class="flex gap-2 mb-5 overflow-x-auto pb-1">
      <button v-for="t in [['pool','旧货池'], ['claims','我的认领'], ['products','我的成品']]" :key="t[0]"
        class="px-4 py-2 rounded-full text-sm border whitespace-nowrap transition"
        :class="tab === t[0] ? 'bg-mint-500 text-white border-mint-500' : 'bg-white border-mint-200 text-mint-700'"
        @click="tab = t[0]">{{ t[1] }}</button>
    </div>

    <!-- ① 旧货池：仅管理员审核通过的 -->
    <div v-if="tab === 'pool'" class="space-y-3">
      <p class="text-xs text-gray-400">这里只显示管理员已审核通过的旧货。看不到的物品说明还在审核中。</p>
      <div v-for="s in pool" :key="s.id" class="card flex gap-3 items-start">
        <img v-if="s.images?.[0]" :src="s.images[0]" class="w-16 h-16 rounded-xl object-cover shrink-0" />
        <div v-else class="w-16 h-16 bg-mint-50 rounded-xl grid place-items-center text-xl shrink-0">📦</div>
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2">
            <h3 class="font-medium text-sm">{{ s.title }}</h3>
            <span class="text-[10px] px-2 py-0.5 rounded-full bg-gray-50 text-gray-500">
              {{ s.source === 'student' ? '学生投稿' : '线下进货' }}
            </span>
          </div>
          <p class="text-xs text-gray-500 mt-1 line-clamp-2">{{ s.description || '无描述' }}</p>
          <button class="mt-2 text-xs bg-mint-500 text-white px-3 py-1.5 rounded-full" @click="claimTarget = s">
            🧑‍🔧 申请认领改造
          </button>
        </div>
      </div>
      <p v-if="!pool.length" class="text-center text-gray-400 py-8">暂无已上架的旧货，等管理员审核吧 🌱</p>
    </div>

    <!-- ② 我的认领 -->
    <div v-if="tab === 'claims'" class="space-y-3">
      <div v-for="c in myClaims" :key="c.id" class="card">
        <div class="flex justify-between items-start gap-3">
          <div class="min-w-0">
            <h4 class="font-medium text-sm">{{ c.stock_items?.title }}</h4>
            <p class="text-xs text-gray-500 mt-1">来源：{{ c.stock_items?.source === 'offline' ? '线下进货' : '学生投稿' }}</p>
            <p class="text-[11px] text-gray-400 mt-1">{{ new Date(c.created_at).toLocaleString() }}</p>
          </div>
          <span class="text-[10px] px-2 py-1 rounded-full shrink-0"
            :class="c.status === 'new' ? 'bg-amber-100 text-amber-600' : c.status === 'done' ? 'bg-mint-100 text-mint-700' : 'bg-blue-100 text-blue-600'">
            {{ CLAIM_STATUS[c.status] }}
          </span>
        </div>
        <button v-if="c.status === 'delivered'" class="mt-3 text-xs bg-mint-500 text-white px-3 py-1.5 rounded-full" @click="openPublish(c)">
          ✅ 改造完成，上架成品
        </button>
      </div>
      <p v-if="!myClaims.length" class="text-center text-gray-400 py-8">还没有认领记录</p>
    </div>

    <!-- ③ 我的成品 -->
    <div v-if="tab === 'products'" class="grid grid-cols-2 gap-3">
      <div v-for="p in myProducts" :key="p.id" class="card !p-3">
        <img v-if="p.image_after" :src="p.image_after" class="w-full h-32 object-cover rounded-xl" />
        <div v-else class="w-full h-32 bg-mint-100 rounded-xl grid place-items-center text-3xl">🌿</div>
        <p class="text-sm font-medium mt-2 truncate">{{ p.name }}</p>
        <div class="flex justify-between items-center mt-1">
          <span class="text-mint-600 font-bold text-sm">¥{{ p.price }}</span>
          <span class="text-[10px] text-gray-400">{{ p.status === 'online' ? '在售' : '已下架' }}</span>
        </div>
      </div>
      <p v-if="!myProducts.length" class="text-sm text-gray-400 col-span-2 text-center py-8">还没有上架过成品</p>
    </div>

    <!-- 认领留言弹窗 -->
    <Teleport to="body">
      <div v-if="claimTarget" class="fixed inset-0 z-50 bg-black/40 flex items-end md:items-center justify-center" @click.self="claimTarget = null">
        <div class="bg-cream w-full md:max-w-md rounded-t-3xl md:rounded-3xl p-6">
          <h3 class="font-bold text-mint-700 mb-1">申请认领「{{ claimTarget.title }}」</h3>
          <p class="text-xs text-gray-400 mb-4">说说你的改造思路，管理员审核通过后会线下把物品交给你</p>
          <textarea v-model="claimNote" rows="3" placeholder="例如：我想把它打磨上漆，改成带抽屉的床头柜…" class="w-full border border-gray-200 rounded-xl px-3 py-2.5 text-sm" />
          <div class="flex gap-2 mt-4">
            <button class="btn-ghost flex-1" @click="claimTarget = null">取消</button>
            <button class="btn-primary flex-1" @click="submitClaim">提交申请</button>
          </div>
        </div>
      </div>
    </Teleport>

    <!-- 成品上架弹窗 -->
    <Teleport to="body">
      <div v-if="publishTarget" class="fixed inset-0 z-50 bg-black/40 flex items-end md:items-center justify-center overflow-y-auto" @click.self="publishTarget = null">
        <div class="bg-cream w-full md:max-w-lg rounded-t-3xl md:rounded-3xl p-6 my-8 max-h-[90vh] overflow-y-auto">
          <h3 class="font-bold text-mint-700 mb-1">✅ 上架改造成品</h3>
          <p class="text-xs text-gray-400 mb-4">来源：{{ publishTarget.stock_items?.title }}</p>
          <div class="space-y-3">
            <input v-model="form.name" placeholder="成品名称（如：复古风床头柜）" class="input" />
            <div class="grid grid-cols-2 gap-3">
              <select v-model="form.zone" class="input">
                <option value="bed">床区域</option><option value="desk">书桌</option><option value="nightstand">床头柜</option>
                <option value="shelf">置物架</option><option value="floor">地面收纳区</option>
              </select>
              <input v-model.number="form.price" type="number" min="0" placeholder="售价 ¥" class="input" />
            </div>
            <textarea v-model="form.description" rows="2" placeholder="商品描述" class="input" />
            <textarea v-model="form.story" rows="3" placeholder="📖 改造故事（怎么改的、花了多少心思）" class="input" />
            <input v-model="form.image_after" placeholder="改造后照片 URL（第③步，可选）" class="input" />
            <input v-model="form.process" placeholder="改造过程照片 URL（第②步，可选）" class="input" />
          </div>
          <div class="flex gap-2 mt-5">
            <button class="btn-ghost flex-1" @click="publishTarget = null">取消</button>
            <button class="btn-primary flex-1" @click="publishProduct">确认上架</button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
.input { @apply w-full border border-gray-200 rounded-xl px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-mint-300; }
</style>
