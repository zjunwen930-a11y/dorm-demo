<script setup>
/**
 * 改造商城 v4 —— 两类商品（✨翻新二手 / 🎨社团改造）
 * 功能：搜索 / 排序（含热度）/ 分区筛选 / 热门趋势榜 / 详情弹窗（三步过程图）/ 收藏 / 购买意向
 */
import { ref, onMounted, computed } from 'vue'
import { supabase } from '../lib/supabase'
import { useAuth } from '../stores/auth'

const { user } = useAuth()
const products = ref([])
const hotMap = ref({})          // product_id -> { order_count, fav_count, hot_score }
const favIds = ref(new Set())
const q = ref('')
const sort = ref('new')         // new / priceAsc / priceDesc / hot
const filter = ref('all')
const kind = ref('all')         // all / refurbished / diy
const tip = ref('')
const loading = ref(true)
const detail = ref(null)

const ZONES = [
  { key: 'all', label: '全部' },
  { key: 'bed', label: '床区域' },
  { key: 'desk', label: '书桌' },
  { key: 'nightstand', label: '床头柜' },
  { key: 'shelf', label: '置物架' },
  { key: 'floor', label: '地面收纳区' },
]
const SORTS = [
  { key: 'new', label: '最新上架' },
  { key: 'hot', label: '热度最高' },
  { key: 'priceAsc', label: '价格从低到高' },
  { key: 'priceDesc', label: '价格从高到低' },
]

/** 热门趋势榜：取热度前 3 */
const hotTop = computed(() => {
  const list = products.value
    .map(p => ({ ...p, hot: hotMap.value[p.id] }))
    .filter(p => p.hot && p.hot.hot_score > 0)
    .sort((a, b) => b.hot.hot_score - a.hot.hot_score)
  return list.slice(0, 3)
})

async function load() {
  loading.value = true
  let query = supabase.from('products').select('*')
  if (filter.value !== 'all') query = query.eq('zone', filter.value)
  if (kind.value !== 'all') query = query.eq('kind', kind.value)
  if (q.value.trim()) query = query.or(`name.ilike.%${q.value.trim()}%,description.ilike.%${q.value.trim()}%`)

  if (sort.value === 'priceAsc') query = query.order('price', { ascending: true })
  else if (sort.value === 'priceDesc') query = query.order('price', { ascending: false })
  else query = query.order('created_at', { ascending: false })

  const { data } = await query
  products.value = data ?? []

  // 热度排序在本地做（聚合数据来自数据库函数）
  if (sort.value === 'hot') {
    products.value = [...products.value].sort(
      (a, b) => (hotMap.value[b.id]?.hot_score ?? 0) - (hotMap.value[a.id]?.hot_score ?? 0)
    )
  }
  loading.value = false
}

/** 拉取热度聚合数据（数据库函数 hot_products，只返回数字不泄露订单明细） */
async function loadHot() {
  const { data, error } = await supabase.rpc('hot_products')
  if (error) return   // 若尚未运行 upgrade3.sql，榜单自动为空，不影响主流程
  const map = {}
  ;(data ?? []).forEach(r => { map[r.product_id] = r })
  hotMap.value = map
}

async function loadFavs() {
  if (!user.value) return
  const { data } = await supabase.from('favorites').select('product_id').eq('user_id', user.value.id)
  favIds.value = new Set((data ?? []).map(d => d.product_id))
}

onMounted(async () => { await Promise.all([loadHot(), load(), loadFavs()]) })

async function toggleFav(p) {
  if (!user.value) { tip.value = '请先登录后再收藏'; return }
  if (favIds.value.has(p.id)) {
    await supabase.from('favorites').delete().eq('user_id', user.value.id).eq('product_id', p.id)
    favIds.value.delete(p.id)
  } else {
    await supabase.from('favorites').insert({ user_id: user.value.id, product_id: p.id })
    favIds.value.add(p.id)
  }
  favIds.value = new Set(favIds.value)
  loadHot()
}

/** 提交购买意向；成功后解锁宿舍盲盒 */
async function buy(p) {
  if (!user.value) { tip.value = '请先登录后再提交购买意向'; return }
  const { error } = await supabase.from('orders').insert({ product_id: p.id, buyer: user.value.id })
  if (error) {
    tip.value = error.code === '23505' ? '你已经提交过这件商品的意向啦' : '提交失败：' + error.message
    return
  }
  tip.value = `已提交「${p.name}」的购买意向 ✓ 🎁 已解锁一次宿舍盲盒`
  localStorage.setItem('dorm-pending-box', '1')   // 首页读取后随机换肤
  window.dispatchEvent(new Event('dorm-unlock'))
  loadHot()
}

function isFav(p) { return favIds.value.has(p.id) }
</script>

<template>
  <div class="max-w-5xl mx-auto px-4 py-8">
    <h1 class="text-xl font-bold text-mint-700 mb-1">🛒 改造商城</h1>
    <p class="text-sm text-gray-500 mb-4">两类好物：管理员筛选翻新的二手物品，以及 DIY 社团改造创作的创意成品。</p>

    <!-- 搜索 + 排序 -->
    <div class="flex gap-2 mb-3">
      <div class="relative flex-1">
        <input v-model="q" @keyup.enter="load" placeholder="搜索商品名称或描述…" class="w-full border border-gray-200 rounded-full pl-9 pr-3 py-2 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-mint-300" />
        <span class="absolute left-3 top-2 text-gray-400">🔍</span>
      </div>
      <select v-model="sort" class="border border-gray-200 rounded-full px-3 py-2 text-sm bg-white" @change="load">
        <option v-for="s in SORTS" :key="s.key" :value="s.key">{{ s.label }}</option>
      </select>
    </div>

    <!-- 类型筛选 -->
    <div class="flex gap-2 mb-2">
      <button v-for="k in [{ key: 'all', label: '全部好物' }, { key: 'refurbished', label: '✨ 翻新二手' }, { key: 'diy', label: '🎨 社团改造' }]"
        :key="k.key" @click="kind = k.key; load()"
        class="px-4 py-1.5 rounded-full text-sm border transition"
        :class="kind === k.key ? 'bg-white border-mint-500 text-mint-700 font-medium shadow-sm' : 'bg-white/60 border-gray-200 text-gray-500'">
        {{ k.label }}
      </button>
    </div>

    <!-- 分区筛选 -->
    <div class="flex gap-2 overflow-x-auto pb-2 mb-4">
      <button v-for="z in ZONES" :key="z.key" @click="filter = z.key; load()"
        class="px-3.5 py-1.5 rounded-full text-sm whitespace-nowrap border transition"
        :class="filter === z.key ? 'bg-mint-500 text-white border-mint-500' : 'bg-white border-mint-200 text-mint-700'">
        {{ z.label }}
      </button>
    </div>

    <p v-if="tip" class="text-sm bg-mint-100 text-mint-700 rounded-xl px-4 py-2.5 mb-4">{{ tip }}</p>

    <!-- 🔥 热门趋势榜 -->
    <section v-if="hotTop.length" class="card mb-5 !p-4">
      <div class="flex items-center justify-between mb-2.5">
        <h2 class="font-bold text-mint-700 text-sm">🔥 改造物品热门趋势榜</h2>
        <span class="text-[10px] text-gray-400">按 购买意向×3 + 收藏×1 计算</span>
      </div>
      <div class="space-y-2">
        <button v-for="(p, i) in hotTop" :key="p.id" class="w-full flex items-center gap-3 text-left" @click="detail = p">
          <span class="text-lg w-6 text-center">{{ ['🥇','🥈','🥉'][i] }}</span>
          <img v-if="p.image_after" :src="p.image_after" class="w-9 h-9 rounded-lg object-cover" />
          <div v-else class="w-9 h-9 rounded-lg bg-mint-100 grid place-items-center text-sm">🌿</div>
          <div class="min-w-0 flex-1">
            <p class="text-sm truncate">{{ p.name }}</p>
            <p class="text-[11px] text-gray-400">意向 {{ p.hot.order_count }} · 收藏 {{ p.hot.fav_count }}</p>
          </div>
          <span class="text-sm font-bold text-mint-600">¥{{ p.price }}</span>
        </button>
      </div>
    </section>

    <div v-if="loading" class="text-center text-gray-400 py-10">加载中…</div>
    <div v-else-if="!products.length" class="text-center text-gray-400 py-10">没有找到匹配的商品 🌱</div>

    <div class="grid grid-cols-2 md:grid-cols-3 gap-4">
      <article v-for="p in products" :key="p.id" class="card !p-3 flex flex-col cursor-pointer" @click="detail = p">
        <div class="relative">
          <img v-if="p.image_after" :src="p.image_after" class="w-full h-36 object-cover rounded-xl" />
          <div v-else class="w-full h-36 bg-mint-100 rounded-xl grid place-items-center text-mint-400 text-3xl">🌿</div>
          <span class="absolute top-2 left-2 text-[10px] px-2 py-0.5 rounded-full bg-white/90 backdrop-blur"
            :class="p.kind === 'refurbished' ? 'text-amber-600' : 'text-mint-700'">
            {{ p.kind === 'refurbished' ? '✨ 翻新二手' : '🎨 社团改造' }}
          </span>
          <button class="absolute top-2 right-2 w-8 h-8 rounded-full bg-white/90 shadow grid place-items-center text-sm hover:scale-110 transition"
            :title="isFav(p) ? '取消收藏' : '收藏'" @click.stop="toggleFav(p)">
            {{ isFav(p) ? '❤️' : '🤍' }}
          </button>
        </div>
        <h3 class="font-medium mt-2 truncate">{{ p.name }}</h3>
        <p class="text-xs text-gray-500 line-clamp-2 mt-1 flex-1">{{ p.description }}</p>
        <p v-if="hotMap[p.id]?.hot_score" class="text-[10px] text-amber-500 mt-1">🔥 热度 {{ hotMap[p.id].hot_score }}</p>
        <div class="flex items-center justify-between mt-2">
          <span class="text-mint-600 font-bold">¥{{ p.price }}</span>
          <button class="text-xs bg-mint-500 text-white px-3 py-1.5 rounded-full hover:bg-mint-600"
            @click.stop="buy(p)">购买意向</button>
        </div>
      </article>
    </div>

    <!-- 商品详情弹窗：三步过程图 -->
    <Teleport to="body">
      <div v-if="detail" class="fixed inset-0 z-50 bg-black/40 flex items-end md:items-center justify-center" @click.self="detail = null">
        <div class="bg-cream w-full md:max-w-lg rounded-t-3xl md:rounded-3xl max-h-[88vh] overflow-y-auto">
          <div class="relative">
            <img v-if="detail.image_after" :src="detail.image_after" class="w-full h-56 object-cover rounded-t-3xl" />
            <div v-else class="w-full h-40 bg-mint-100 rounded-t-3xl grid place-items-center text-5xl">🌿</div>
            <button class="absolute top-3 right-3 w-8 h-8 rounded-full bg-white/90 shadow grid place-items-center" @click="detail = null">✕</button>
            <button class="absolute top-3 left-3 w-8 h-8 rounded-full bg-white/90 shadow grid place-items-center"
              @click="toggleFav(detail)">{{ isFav(detail) ? '❤️' : '🤍' }}</button>
          </div>
          <div class="p-5">
            <div class="flex items-start justify-between gap-3">
              <h2 class="text-lg font-bold">{{ detail.name }}</h2>
              <span class="text-mint-600 font-bold text-xl shrink-0">¥{{ detail.price }}</span>
            </div>
            <div class="flex flex-wrap gap-1.5 mt-2">
              <span class="text-xs px-2.5 py-1 rounded-full"
                :class="detail.kind === 'refurbished' ? 'bg-amber-50 text-amber-600' : 'bg-mint-100 text-mint-700'">
                {{ detail.kind === 'refurbished' ? '✨ 管理员翻新二手' : '🎨 DIY社团改造' }}
              </span>
              <span class="text-xs bg-white text-gray-500 px-2.5 py-1 rounded-full border border-gray-100">
                {{ { bed: '床区域', desk: '书桌', nightstand: '床头柜', shelf: '置物架', floor: '地面收纳区' }[detail.zone] }}
              </span>
            </div>
            <p class="text-sm text-gray-600 mt-3">{{ detail.description }}</p>

            <!-- 三步过程图 -->
            <div class="mt-4 bg-white rounded-2xl p-4 border border-mint-100">
              <h3 class="text-sm font-bold text-mint-700 mb-3">📸 它的三步新生过程</h3>
              <div class="grid grid-cols-3 gap-2">
                <div class="text-center">
                  <img v-if="detail.image_before" :src="detail.image_before" class="w-full h-20 object-cover rounded-lg" />
                  <div v-else class="w-full h-20 rounded-lg bg-gray-100 grid place-items-center text-[10px] text-gray-400">暂无照片</div>
                  <p class="text-[11px] mt-1 text-gray-500">① 回收筛选</p>
                </div>
                <div class="text-center">
                  <img v-if="detail.process_images?.[0]" :src="detail.process_images[0]" class="w-full h-20 object-cover rounded-lg" />
                  <div v-else class="w-full h-20 rounded-lg bg-gray-100 grid place-items-center text-[10px] text-gray-400">暂无照片</div>
                  <p class="text-[11px] mt-1 text-gray-500">② {{ detail.kind === 'refurbished' ? '清洁翻新' : '改造过程' }}</p>
                </div>
                <div class="text-center">
                  <img v-if="detail.image_after" :src="detail.image_after" class="w-full h-20 object-cover rounded-lg" />
                  <div v-else class="w-full h-20 rounded-lg bg-mint-50 grid place-items-center text-[10px] text-mint-400">暂无照片</div>
                  <p class="text-[11px] mt-1 text-gray-500">③ 焕新上架</p>
                </div>
              </div>
            </div>

            <!-- 改造故事 -->
            <div v-if="detail.story" class="mt-4 bg-white rounded-2xl p-4 border border-mint-100">
              <h3 class="text-sm font-bold text-mint-700 mb-1.5">📖 背后的故事</h3>
              <p class="text-sm text-gray-600 leading-relaxed">{{ detail.story }}</p>
            </div>

            <button class="btn-primary w-full mt-5" @click="buy(detail)">提交购买意向（解锁一次盲盒）</button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>
