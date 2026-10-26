<script setup>
/**
 * 管理员后台 v3 —— 供应链上游的总控台（仅 admin）
 * Tab：旧货池 / 认领申请 / 成品管理 / 购买意向 / 用户角色
 *
 * 业务流程（两条出路）：
 *   学生投稿 / 线下进货 → 旧货池(pending)
 *   → 管理员审核后二选一：
 *       ① 自己翻新后直接上架（products.kind = refurbished）→ 学生可直接买
 *       ② 开放给社团认领（available）→ 社团申请 → 管理员发货 → 社团改造后上架（kind = diy）
 */
import { ref, onMounted } from 'vue'
import { supabase } from '../lib/supabase'
import { useAuth } from '../stores/auth'

const { user } = useAuth()
const tab = ref('stock')
const stocks = ref([])     // 旧货池（全部状态）
const claims = ref([])     // 认领申请
const products = ref([])   // 成品（翻新二手 + 社团成品）
const orders = ref([])     // 购买意向
const users = ref([])      // 用户
const message = ref('')
const overview = ref({ users: 0, pending: 0, products: 0, orders: 0 })

// 线下进货表单
const stockForm = ref({ title: '', category: '家具', description: '', cost: 0, image: '' })
const showStockForm = ref(false)

// 翻新上架弹窗
const refurbTarget = ref(null)
const refurbForm = ref({ name: '', price: 39, zone: 'floor', description: '', image_after: '', process: '' })

const STOCK_STATUS = {
  pending: '待审核', available: '开放认领', onsale: '已翻新上架',
  assigned: '社团改造中', converted: '社团已改造',
}
const CLAIM_STATUS = { new: '申请中', accepted: '已通过', delivered: '已发货', done: '已完成' }
const KIND_TEXT = { refurbished: '翻新二手', diy: '社团改造' }

async function load() {
  const [s, c, p, o, u, c1, c2, c3, c4] = await Promise.all([
    supabase.from('stock_items').select('*').order('created_at', { ascending: false }),
    supabase.from('claims').select('*, stock_items(title), profiles(nickname)').order('created_at', { ascending: false }),
    supabase.from('products').select('*').order('created_at', { ascending: false }),
    supabase.from('orders').select('*, products(name)').order('created_at', { ascending: false }),
    supabase.from('profiles').select('*').order('created_at', { ascending: false }),
    supabase.from('profiles').select('id', { count: 'exact', head: true }),
    supabase.from('stock_items').select('id', { count: 'exact', head: true }).eq('status', 'pending'),
    supabase.from('products').select('id', { count: 'exact', head: true }),
    supabase.from('orders').select('id', { count: 'exact', head: true }),
  ])
  stocks.value = s.data ?? []
  claims.value = c.data ?? []
  products.value = p.data ?? []
  orders.value = o.data ?? []
  users.value = u.data ?? []
  overview.value = { users: c1.count ?? 0, pending: c2.count ?? 0, products: c3.count ?? 0, orders: c4.count ?? 0 }
}
onMounted(load)

/** 出路①：开放给社团认领（进入社团可见的旧货池） */
async function freeToClub(item) {
  const { error } = await supabase.from('stock_items').update({ status: 'available' }).eq('id', item.id)
  if (!error && item.post_id) {
    await supabase.from('recycle_posts').update({ status: 'claimed' }).eq('id', item.post_id)
  }
  message.value = error ? '操作失败：' + error.message : `「${item.title}」已开放给社团认领 ✓`
  load()
}

/** 出路②：打开「翻新后直接上架」弹窗 */
function openRefurbish(item) {
  refurbTarget.value = item
  refurbForm.value = {
    name: item.title,
    price: 39,
    zone: 'floor',
    description: item.description || '经管理员清洁、修补、翻新后上架，功能完好。',
    image_after: item.images?.[0] ?? '',
    process: '',
  }
}

/** 提交翻新上架：生成 kind=refurbished 的商品，旧货标记为已翻新上架 */
async function publishRefurbished() {
  const item = refurbTarget.value
  const { error } = await supabase.from('products').insert({
    name: refurbForm.value.name,
    price: Number(refurbForm.value.price) || 0,
    zone: refurbForm.value.zone,
    description: refurbForm.value.description,
    image_before: item.images?.[0] ?? null,
    image_after: refurbForm.value.image_after || null,
    process_images: refurbForm.value.process ? [refurbForm.value.process] : [],
    story: '这件物品由平台线下回收，经管理员筛选、清洁与翻新后重新上架，让好东西继续被使用。',
    stock_id: item.id,
    creator: user.value.id,
    kind: 'refurbished',
    status: 'online',
  })
  if (error) { message.value = '上架失败：' + error.message; return }
  await supabase.from('stock_items').update({ status: 'onsale' }).eq('id', item.id)
  if (item.post_id) await supabase.from('recycle_posts').update({ status: 'done' }).eq('id', item.post_id)
  message.value = '翻新二手已上架 ✓ 学生现在可以在商城看到它'
  refurbTarget.value = null
  load()
}

async function rejectStock(item) {
  if (!confirm(`确定驳回「${item.title}」吗？该记录会被删除。`)) return
  const { error } = await supabase.from('stock_items').delete().eq('id', item.id)
  message.value = error ? '操作失败：' + error.message : '已驳回'
  load()
}

/** 线下进货：管理员自己录入旧货，可直接上架或先待审 */
async function addStock(online = true) {
  if (!stockForm.value.title.trim()) { message.value = '请填写物品名称'; return }
  const { error } = await supabase.from('stock_items').insert({
    title: stockForm.value.title.trim(),
    category: stockForm.value.category,
    description: stockForm.value.description,
    cost: Number(stockForm.value.cost) || 0,
    images: stockForm.value.image ? [stockForm.value.image] : [],
    source: 'offline',
    status: online ? 'available' : 'pending',
  })
  message.value = error ? '录入失败：' + error.message : '线下旧货已录入 ✓'
  if (!error) {
    stockForm.value = { title: '', category: '家具', description: '', cost: 0, image: '' }
    showStockForm.value = false
  }
  load()
}

/** 处理认领：通过并标记发货 → 旧货变为「社团改造中」 */
async function deliverClaim(c) {
  const { error } = await supabase.from('claims').update({ status: 'delivered' }).eq('id', c.id)
  if (!error) await supabase.from('stock_items').update({ status: 'assigned' }).eq('id', c.stock_id)
  message.value = error ? '操作失败：' + error.message : '已通过并标记发货，请线下把物品交给社团 ✓'
  load()
}

async function rejectClaim(c) {
  if (!confirm('确定驳回该认领申请吗？')) return
  const { error } = await supabase.from('claims').delete().eq('id', c.id)
  message.value = error ? '操作失败：' + error.message : '已驳回申请'
  load()
}

/** 成品上下架 */
async function toggleProduct(p) {
  const { error } = await supabase.from('products')
    .update({ status: p.status === 'online' ? 'offline' : 'online' }).eq('id', p.id)
  message.value = error ? '操作失败：' + error.message : '已更新商品状态 ✓'
  load()
}

/** 修改用户角色（后端鉴权入口） */
async function setRole(profile, role) {
  const { error } = await supabase.from('profiles').update({ role }).eq('id', profile.id)
  message.value = error ? '修改失败：' + error.message : `已将用户设为 ${role} ✓（对方重新登录后生效）`
  load()
}

function withdrawOrder(o) {
  supabase.from('orders').update({ status: 'contacted' }).eq('id', o.id).then(load)
}
</script>

<template>
  <div class="max-w-4xl mx-auto px-4 py-8">
    <h1 class="text-xl font-bold text-mint-700 mb-1">⚙️ 管理员后台</h1>
    <p class="text-xs text-gray-400 mb-4">旧货准入 → 审核上架 → 社团认领发货 → 成品上下架</p>

    <p v-if="message" class="text-sm bg-mint-100 text-mint-700 rounded-xl px-4 py-2.5 mb-4">{{ message }}</p>

    <!-- 数据总览 -->
    <section class="grid grid-cols-4 gap-2.5 mb-5">
      <div class="card !p-3 text-center"><p class="text-lg font-bold text-mint-600">{{ overview.users }}</p><p class="text-[11px] text-gray-500">用户</p></div>
      <div class="card !p-3 text-center"><p class="text-lg font-bold text-amber-500">{{ overview.pending }}</p><p class="text-[11px] text-gray-500">待审旧货</p></div>
      <div class="card !p-3 text-center"><p class="text-lg font-bold text-mint-600">{{ overview.products }}</p><p class="text-[11px] text-gray-500">成品</p></div>
      <div class="card !p-3 text-center"><p class="text-lg font-bold text-mint-600">{{ overview.orders }}</p><p class="text-[11px] text-gray-500">购买意向</p></div>
    </section>

    <!-- Tab -->
    <div class="flex gap-2 mb-5 overflow-x-auto pb-1">
      <button v-for="t in [['stock','旧货池'], ['claims','认领申请'], ['products','成品管理'], ['orders','购买意向'], ['users','用户角色']]" :key="t[0]"
        class="px-3.5 py-2 rounded-full text-sm border whitespace-nowrap transition"
        :class="tab === t[0] ? 'bg-mint-500 text-white border-mint-500' : 'bg-white border-mint-200 text-mint-700'"
        @click="tab = t[0]">{{ t[1] }}</button>
    </div>

    <!-- ① 旧货池：审核 + 线下进货 -->
    <div v-if="tab === 'stock'" class="space-y-3">
      <button class="btn-ghost w-full !py-2 text-sm" @click="showStockForm = !showStockForm">
        {{ showStockForm ? '收起录入表单' : '➕ 线下进货 / 录入旧货' }}
      </button>

      <!-- 线下进货表单 -->
      <div v-if="showStockForm" class="card space-y-3">
        <input v-model="stockForm.title" placeholder="物品名称（如：二手实木书架）" class="input" />
        <div class="grid grid-cols-2 gap-3">
          <select v-model="stockForm.category" class="input">
            <option>家具</option><option>电器</option><option>织物</option><option>书籍</option><option>其他</option>
          </select>
          <input v-model.number="stockForm.cost" type="number" min="0" placeholder="进货成本 ¥" class="input" />
        </div>
        <textarea v-model="stockForm.description" rows="2" placeholder="物品现状，方便社团评估改造成本" class="input" />
        <input v-model="stockForm.image" placeholder="图片 URL（可选）" class="input" />
        <div class="flex gap-2">
          <button class="btn-ghost flex-1 !py-2 text-sm" @click="addStock(false)">先入库待审</button>
          <button class="btn-primary flex-1 !py-2 text-sm" @click="addStock(true)">开放给社团认领</button>
        </div>
      </div>

      <!-- 旧货列表 -->
      <div v-for="s in stocks" :key="s.id" class="card flex gap-3 items-start">
        <img v-if="s.images?.[0]" :src="s.images[0]" class="w-16 h-16 rounded-xl object-cover shrink-0" />
        <div v-else class="w-16 h-16 bg-mint-50 rounded-xl grid place-items-center text-xl shrink-0">📦</div>
        <div class="flex-1 min-w-0">
          <div class="flex items-center gap-2 flex-wrap">
            <h3 class="font-medium text-sm">{{ s.title }}</h3>
            <span class="text-[10px] px-2 py-0.5 rounded-full"
              :class="s.status === 'pending' ? 'bg-amber-100 text-amber-600' : s.status === 'available' ? 'bg-mint-100 text-mint-700' : s.status === 'assigned' ? 'bg-blue-100 text-blue-600' : 'bg-gray-100 text-gray-500'">
              {{ STOCK_STATUS[s.status] }}
            </span>
            <span class="text-[10px] px-2 py-0.5 rounded-full bg-gray-50 text-gray-500">
              {{ s.source === 'student' ? '学生投稿' : '线下进货' }}
            </span>
          </div>
          <p class="text-xs text-gray-500 mt-1 line-clamp-2">{{ s.description || '无描述' }}</p>
          <p v-if="s.source === 'offline'" class="text-[11px] text-gray-400 mt-0.5">进货成本 ¥{{ s.cost }}</p>
          <div v-if="s.status === 'pending'" class="flex flex-wrap gap-2 mt-2">
            <button class="text-xs bg-mint-500 text-white px-3 py-1.5 rounded-full" @click="openRefurbish(s)">✨ 翻新后上架</button>
            <button class="text-xs border border-mint-400 text-mint-600 px-3 py-1.5 rounded-full" @click="freeToClub(s)">🤝 开放给社团认领</button>
            <button class="text-xs border border-red-200 text-red-500 px-3 py-1.5 rounded-full" @click="rejectStock(s)">✕ 驳回</button>
          </div>
        </div>
      </div>
      <p v-if="!stocks.length" class="text-center text-gray-400 py-8">旧货池还是空的</p>
    </div>

    <!-- ② 认领申请 -->
    <div v-if="tab === 'claims'" class="space-y-3">
      <div v-for="c in claims" :key="c.id" class="card">
        <div class="flex justify-between items-start gap-3">
          <div class="min-w-0">
            <h4 class="font-medium text-sm">🧑‍🔧 {{ c.profiles?.nickname || '社团成员' }} 申请认领「{{ c.stock_items?.title }}」</h4>
            <p v-if="c.note" class="text-xs text-gray-600 mt-1">留言：{{ c.note }}</p>
            <p class="text-[11px] text-gray-400 mt-1">{{ new Date(c.created_at).toLocaleString() }}</p>
          </div>
          <span class="text-[10px] px-2 py-1 rounded-full shrink-0"
            :class="c.status === 'new' ? 'bg-amber-100 text-amber-600' : c.status === 'done' ? 'bg-mint-100 text-mint-700' : 'bg-blue-100 text-blue-600'">
            {{ CLAIM_STATUS[c.status] }}
          </span>
        </div>
        <div v-if="c.status === 'new'" class="flex gap-2 mt-3">
          <button class="text-xs bg-mint-500 text-white px-3 py-1.5 rounded-full" @click="deliverClaim(c)">✓ 通过并发货</button>
          <button class="text-xs border border-red-200 text-red-500 px-3 py-1.5 rounded-full" @click="rejectClaim(c)">✕ 驳回</button>
        </div>
      </div>
      <p v-if="!claims.length" class="text-center text-gray-400 py-8">暂无认领申请</p>
    </div>

    <!-- ③ 成品管理 -->
    <div v-if="tab === 'products'" class="space-y-2.5">
      <div v-for="p in products" :key="p.id" class="card flex items-center gap-3">
        <img v-if="p.image_after" :src="p.image_after" class="w-12 h-12 rounded-lg object-cover shrink-0" />
        <div class="flex-1 min-w-0">
          <p class="text-sm font-medium truncate">{{ p.name }}</p>
          <p class="text-xs text-gray-500">
            <span class="px-1.5 py-0.5 rounded bg-gray-50 text-gray-500 mr-1">{{ KIND_TEXT[p.kind] ?? '社团改造' }}</span>
            ¥{{ p.price }} · {{ p.status === 'online' ? '在售' : '已下架' }}
          </p>
        </div>
        <button class="text-xs px-3 py-1.5 rounded-full border transition shrink-0"
          :class="p.status === 'online' ? 'border-amber-300 text-amber-600' : 'border-mint-400 text-mint-600'"
          @click="toggleProduct(p)">{{ p.status === 'online' ? '下架' : '上架' }}</button>
      </div>
      <p v-if="!products.length" class="text-center text-gray-400 py-8">暂无成品</p>
    </div>

    <!-- ④ 购买意向 -->
    <div v-if="tab === 'orders'" class="space-y-2.5">
      <div v-for="o in orders" :key="o.id" class="card flex justify-between items-center gap-3">
        <div class="min-w-0">
          <p class="text-sm font-medium truncate">{{ o.products?.name ?? '商品' }}</p>
          <p class="text-[11px] text-gray-400">{{ new Date(o.created_at).toLocaleString() }}</p>
        </div>
        <button v-if="o.status === 'new'" class="text-xs bg-mint-500 text-white px-3 py-1.5 rounded-full shrink-0" @click="withdrawOrder(o)">标记已联系</button>
        <span v-else class="text-[10px] px-2 py-1 rounded-full bg-mint-100 text-mint-700 shrink-0">已联系</span>
      </div>
      <p v-if="!orders.length" class="text-center text-gray-400 py-8">暂无购买意向</p>
    </div>

    <!-- ⑤ 用户角色 -->
    <div v-if="tab === 'users'" class="card space-y-2">
      <div v-for="u in users" :key="u.id" class="flex items-center justify-between gap-2 py-2 border-b border-gray-50 last:border-0">
        <div class="min-w-0">
          <p class="text-sm truncate">{{ u.nickname || '未命名' }}</p>
          <p class="text-[11px] text-gray-400">碳积分 {{ u.points ?? 0 }}</p>
        </div>
        <select :value="u.role" class="text-xs border rounded-lg px-2 py-1.5 shrink-0" @change="setRole(u, $event.target.value)">
          <option value="student">普通学生</option>
          <option value="member">DIY社团成员</option>
          <option value="admin">管理员</option>
        </select>
      </div>
    </div>

    <!-- 翻新上架弹窗：管理员把旧货翻新后直接卖给同学 -->
    <Teleport to="body">
      <div v-if="refurbTarget" class="fixed inset-0 z-50 bg-black/40 flex items-end md:items-center justify-center overflow-y-auto" @click.self="refurbTarget = null">
        <div class="bg-cream w-full md:max-w-lg rounded-t-3xl md:rounded-3xl p-6 my-8 max-h-[90vh] overflow-y-auto">
          <h3 class="font-bold text-mint-700 mb-1">✨ 翻新后上架</h3>
          <p class="text-xs text-gray-400 mb-4">来源：{{ refurbTarget.title }}（{{ refurbTarget.source === 'offline' ? '线下进货' : '学生投稿' }}）</p>
          <div class="space-y-3">
            <input v-model="refurbForm.name" placeholder="上架名称（如：翻新实木书架）" class="input" />
            <div class="grid grid-cols-2 gap-3">
              <select v-model="refurbForm.zone" class="input">
                <option value="bed">床区域</option><option value="desk">书桌</option><option value="nightstand">床头柜</option>
                <option value="shelf">置物架</option><option value="floor">地面收纳区</option>
              </select>
              <input v-model.number="refurbForm.price" type="number" min="0" placeholder="售价 ¥" class="input" />
            </div>
            <textarea v-model="refurbForm.description" rows="2" placeholder="物品现状与翻新说明" class="input" />
            <input v-model="refurbForm.image_after" placeholder="翻新后照片 URL（第③步，可选）" class="input" />
            <input v-model="refurbForm.process" placeholder="翻新过程照片 URL（第②步，可选）" class="input" />
          </div>
          <div class="flex gap-2 mt-5">
            <button class="btn-ghost flex-1" @click="refurbTarget = null">取消</button>
            <button class="btn-primary flex-1" @click="publishRefurbished">确认上架</button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
.input { @apply w-full border border-gray-200 rounded-xl px-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-mint-300; }
</style>
