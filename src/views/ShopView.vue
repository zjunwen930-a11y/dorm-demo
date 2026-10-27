<script setup>
/**
 * 改造商城 v4 —— 两类商品（✨翻新二手 / 🎨社团改造）
 * 功能：搜索 / 排序（含热度）/ 分区筛选 / 热门趋势榜 / 详情弹窗（三步过程图）/ 收藏 / 购买意向
 */
import { ref, onMounted, computed } from 'vue'
import { supabase } from '../lib/supabase'
import { useModal } from '../composables/useModal'
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
const loadError = ref('')
const detailPanel = ref(null)
useModal(computed(() => Boolean(detail.value)), detailPanel, () => { detail.value = null })
let requestId = 0

function resetFilters() { q.value = ''; filter.value = 'all'; kind.value = 'all'; sort.value = 'new'; load() }

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
  const id = ++requestId
  loading.value = true
  let query = supabase.from('products').select('*')
  if (filter.value !== 'all') query = query.eq('zone', filter.value)
  if (kind.value !== 'all') query = query.eq('kind', kind.value)
  if (q.value.trim()) query = query.or(`name.ilike.%${q.value.trim()}%,description.ilike.%${q.value.trim()}%`)

  if (sort.value === 'priceAsc') query = query.order('price', { ascending: true })
  else if (sort.value === 'priceDesc') query = query.order('price', { ascending: false })
  else query = query.order('created_at', { ascending: false })

  const { data, error } = await query
  if (id !== requestId) return
  loadError.value = error ? '商品暂时未能加载，请稍后重试。' : ''
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
  <div class="page-shell shop-page py-10 md:py-14">
    <section class="shop-intro">
      <div><p class="eyebrow mb-4">THE RENEW COLLECTION</p><h1>好物有来处，<br class="sm:hidden" />生活有新意。</h1><p class="text-sm text-gray-500 mt-4 leading-7">从用心翻新的二手，到社团亲手改造的独一份。<br />为你的小空间，找到刚刚好的那一件。</p></div>
      <p class="shop-note">校园回收 · 用心改造 · 再次相遇<br /><span>仅收集购买意向，无真实支付</span></p>
    </section>
    <!-- 搜索 + 排序 -->
    <form class="search-bar" @submit.prevent="load">
      <div class="relative flex-1">
        <input v-model="q" aria-label="搜索商品名称或描述" placeholder="寻找一盏灯、一张椅子，或一种灵感…" class="w-full border border-gray-200 rounded-lg pl-4 pr-3 py-3 text-sm bg-white focus:outline-none focus:ring-2 focus:ring-mint-300" />

      </div>
      <button class="btn-primary" type="submit">搜索</button>
      <select aria-label="商品排序" v-model="sort" class="border border-gray-200 rounded-lg px-3 py-2 text-sm bg-white" @change="load">
        <option v-for="s in SORTS" :key="s.key" :value="s.key">{{ s.label }}</option>
      </select>
    </form>

    <!-- 类型筛选 -->
    <div class="kind-tabs" aria-label="商品类型">
      <button v-for="k in [{ key: 'all', label: '全部好物' }, { key: 'refurbished', label: '翻新二手' }, { key: 'diy', label: '社团改造' }]"
        :key="k.key" @click="kind = k.key; load()"
        class="kind-tab" :aria-pressed="kind === k.key"
        :class="kind === k.key ? 'is-active' : ''">
        {{ k.label }}
      </button>
    </div>

    <!-- 分区筛选 -->
    <div class="flex gap-2 overflow-x-auto pb-2 mb-4">
      <button v-for="z in ZONES" :key="z.key" @click="filter = z.key; load()"
        class="zone-tab" :aria-pressed="filter === z.key"
        :class="filter === z.key ? 'bg-mint-500 text-white border-mint-500' : 'bg-white border-mint-200 text-mint-700'">
        {{ z.label }}
      </button>
    </div>

    <p v-if="tip" role="status" class="text-sm bg-mint-100 text-mint-700 rounded-xl px-4 py-2.5 mb-4">{{ tip }}</p>

    <!-- 🔥 热门趋势榜 -->
    <section v-if="hotTop.length" class="card mb-5 !p-4">
      <div class="flex items-center justify-between mb-2.5">
        <h2 class="font-bold text-mint-700 text-sm">大家正在关注</h2>
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

    <div class="flex justify-between items-center border-t border-[#dce2d4] pt-5 mb-5"><p class="text-xs text-gray-500" role="status">{{ loading ? '正在寻找好物…' : `本次找到 ${products.length} 件好物` }}</p><button class="text-xs text-mint-700 underline underline-offset-4" @click="resetFilters">重置筛选</button></div>
    <div v-if="loading" class="product-grid" aria-label="正在加载商品" aria-busy="true"><div v-for="i in 6" :key="i" class="skeleton-card"><div></div><span></span><span></span></div></div>
    <div v-else-if="loadError" class="empty-state" role="alert">{{ loadError }} <button class="underline" @click="load">重新加载</button></div>
    <div v-else-if="!products.length" class="empty-state"><p class="text-lg mb-2">暂时没有找到这件好物</p><p>换一个关键词，或看看其他分区。</p><button class="btn-ghost mt-5" @click="resetFilters">查看全部好物</button></div>
    <div v-else class="product-grid">
      <article v-for="p in products" :key="p.id" class="product-card">
        <div class="product-photo">
          <button class="photo-link" :aria-label="`查看${p.name}详情`" @click="detail = p">
            <img v-if="p.image_after" :src="p.image_after" :alt="p.name" loading="lazy" />
            <span v-else class="photo-placeholder">RE / NEW<small>好物，等待被重新发现</small></span>
          </button>
          <span class="product-kind">{{ p.kind === 'refurbished' ? '翻新二手' : '社团改造' }}</span>
          <button class="favorite-button" :aria-label="isFav(p) ? `取消收藏${p.name}` : `收藏${p.name}`" :aria-pressed="isFav(p)" @click="toggleFav(p)">{{ isFav(p) ? '♥' : '♡' }}</button>
        </div>
        <div class="product-copy"><button class="text-left font-medium text-base" @click="detail = p">{{ p.name }}</button><p class="text-xs text-gray-500 leading-6 line-clamp-2 mt-2 flex-1">{{ p.description }}</p><div class="flex justify-between gap-2 items-center mt-4"><span class="product-price"><small>¥</small>{{ p.price }}</span><button class="intent-button" @click="buy(p)">购买意向 ↗</button></div></div>
      </article>
    </div>

    <!-- 商品详情弹窗：三步过程图 -->
    <Teleport to="body">
      <div v-if="detail" class="fixed inset-0 z-50 bg-black/40 flex items-end md:items-center justify-center" @click.self="detail = null">
        <div ref="detailPanel" role="dialog" aria-modal="true" :aria-label="detail.name" tabindex="-1" class="bg-cream w-full md:max-w-lg rounded-t-3xl md:rounded-3xl max-h-[88vh] overflow-y-auto">
          <div class="relative">
            <img v-if="detail.image_after" :src="detail.image_after" class="w-full h-56 object-cover rounded-t-3xl" />
            <div v-else class="w-full h-40 bg-mint-100 rounded-t-3xl grid place-items-center text-5xl">🌿</div>
            <button aria-label="关闭商品详情" class="absolute top-3 right-3 w-8 h-8 rounded-full bg-white/90 shadow grid place-items-center" @click="detail = null">✕</button>
            <button class="absolute top-3 left-3 w-8 h-8 rounded-full bg-white/90 shadow grid place-items-center"
              :aria-label="isFav(detail) ? '取消收藏' : '收藏商品'" @click="toggleFav(detail)">{{ isFav(detail) ? '❤️' : '🤍' }}</button>
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

            <p v-if="tip" role="status" class="mt-4 text-sm text-mint-700">{{ tip }}</p>
            <button class="btn-primary w-full mt-5" @click="buy(detail)">提交购买意向（解锁一次盲盒）</button>
          </div>
        </div>
      </div>
    </Teleport>
  </div>
</template>

<style scoped>
.shop-intro { display: flex; justify-content: space-between; align-items: end; gap: 30px; padding-bottom: 36px; }
.shop-intro h1 { font-size: clamp(30px, 4vw, 42px); font-weight: 600; letter-spacing: -.06em; line-height: 1.4; }
.shop-note { font-size: 11px; line-height: 2.4; text-align: right; color: #718476; }
.shop-note span { font-size: 10px; color: #929b8e; }
.search-bar { display: flex; gap: 10px; background: #edeFE7; padding: 18px; border-radius: 12px; margin-bottom: 26px; }
.kind-tabs { display: flex; gap: 26px; margin-bottom: 20px; border-bottom: 1px solid #dce2d4; }
.kind-tab { font-size: 14px; padding: 0 0 14px; border-bottom: 2px solid transparent; color: #82907f; }
.kind-tab.is-active { color: #284f40; border-bottom-color: #284f40; font-weight: 600; }
.zone-tab { border: 1px solid #dce2d4; padding: 7px 14px; font-size: 12px; white-space: nowrap; border-radius: 6px; }
.product-grid { display: grid; grid-template-columns: repeat(3, minmax(0,1fr)); gap: 28px 22px; }
.product-card { overflow: hidden; background: #fff; border: 1px solid #e1e5dc; border-radius: 12px; display: flex; flex-direction: column; }
.product-photo { position: relative; background: #e8ebdf; }
.photo-link { display: block; width: 100%; height: 240px; overflow: hidden; }
.photo-link img { width: 100%; height: 100%; object-fit: cover; transition: transform .35s; }
.photo-link:hover img { transform: scale(1.04); }
.photo-placeholder { display: flex; flex-direction: column; justify-content: center; height: 100%; gap: 12px; color: #99a88f; letter-spacing: .2em; font-size: 24px; }
.photo-placeholder small { font-size: 10px; letter-spacing: .08em; }
.product-kind { position: absolute; left: 12px; top: 12px; background: #fafaf3e8; padding: 5px 9px; font-size: 10px; border-radius: 4px; pointer-events: none; }
.favorite-button { position: absolute; top: 10px; right: 10px; height: 32px; width: 32px; background: #ffffffea; border-radius: 50%; font-size: 22px; color: #46664e; }
.product-copy { padding: 18px; display: flex; flex-direction: column; flex: 1; }
.product-price { font-size: 22px; font-weight: 500; letter-spacing: -.05em; }
.product-price small { font-size: 13px; margin-right: 3px; }
.intent-button { padding: 7px 11px; border: 1px solid #cbd7c7; border-radius: 6px; font-size: 11px; color: #284f40; }
.intent-button:hover { background: #edf2e9; }
.skeleton-card { background: #fff; border: 1px solid #e1e5dc; border-radius: 12px; overflow: hidden; padding-bottom: 20px; }
.skeleton-card div { height: 240px; background: #e7eadf; }
.skeleton-card span { display: block; height: 12px; background: #eef0e9; margin: 18px 18px 0; width: 60%; }
@media(max-width: 760px) { .product-grid { grid-template-columns: repeat(2, minmax(0,1fr)); gap: 16px; } .shop-note { display: none; } .photo-link, .skeleton-card div { height: 185px; } .search-bar { flex-wrap: wrap; padding: 12px; } .search-bar > div { min-width: 65%; } .search-bar select { width: 100%; } .product-copy { padding: 12px; } }
@media(max-width: 380px) { .product-grid { grid-template-columns: 1fr; } }
</style>
