<script setup>
/**
 * 首页 v2 —— 3D 宿舍 + 公益数据统计 + 环保积分排行榜 + 最新改造推荐
 * 3D 交互是特色附加入口，同时保留常规按钮，保证任何用户都能顺畅使用。
 */
import { ref, onMounted, onBeforeUnmount, computed } from 'vue'
import Dorm3D from '../components/Dorm3D.vue'
import ProductDrawer from '../components/ProductDrawer.vue'
import { supabase } from '../lib/supabase'
import { useAuth } from '../stores/auth'

const { user } = useAuth()

const dormRef = ref(null)
// ---- 家园：购买件数 / 好友 / 亲密度（演示版存本地，P2 接 transfers 表） ----
const orderCount = ref(0)
const intimacy = ref(Number(localStorage.getItem('home-intimacy') ?? 0))
const friendName = ref(localStorage.getItem('home-friend') ?? '')
const DEMO_FRIENDS = ['小林（转赠伙伴）', '阿哲（转赠伙伴）']
const homeLevel = computed(() => orderCount.value >= 5 ? 3 : orderCount.value >= 3 ? 2 : orderCount.value >= 1 ? 1 : 0)
const hasBaby = computed(() => intimacy.value >= 100)

function invite(name) {
  friendName.value = name
  localStorage.setItem('home-friend', name)
  dormRef.value?.inviteFriend(name)
  gain(5)
}
function playTogether() {
  if (!friendName.value) { invite(DEMO_FRIENDS[0]); return }
  dormRef.value?.playTogether()
  gain(10)
}
function makeBaby() {
  if (!hasBaby.value) return
  dormRef.value?.spawnBaby()
}
function gain(n) {
  intimacy.value = Math.min(120, intimacy.value + n)
  localStorage.setItem('home-intimacy', String(intimacy.value))
  if (intimacy.value >= 100) localStorage.setItem('home-baby', '1')
}
const boxToast = ref(null)   // 盲盒解锁提示 { name, desc }
const drawerVisible = ref(false)
const zoneKey = ref('')
const zoneLabel = ref('')

// 公益统计数据
const stats = ref({ posts: 0, products: 0, carbon: 0 })
// 积分排行榜前 5 名
const leaders = ref([])
// 最新上架的 4 件改造商品
const latest = ref([])

const ZONE_LABELS = {
  bed: '床区域', desk: '书桌', nightstand: '床头柜', shelf: '置物架', floor: '地面收纳区',
}

/** 3D 热区/按钮点击 → 打开对应分区商品滑层 */
function openZone(key) {
  zoneKey.value = key
  zoneLabel.value = ZONE_LABELS[key] ?? key
  drawerVisible.value = true
}

/** 开盲盒：随机切换 3D 宿舍主题（下单后触发） */
function openBox() {
  const t = dormRef.value?.randomTheme()   // 返回 { name, desc }
  if (!t) return
  boxToast.value = t
  setTimeout(() => { boxToast.value = null }, 4500)
}

onMounted(async () => {
  // 从商城下单回来后，补开一次盲盒
  if (localStorage.getItem('dorm-pending-box')) {
    localStorage.removeItem('dorm-pending-box')
    setTimeout(openBox, 600)
  }
  window.addEventListener('dorm-unlock', openBox)

  // 并行拉取：投稿数、商品数、排行榜、最新商品
  const [p1, p2, p3, p4, p5] = await Promise.all([
    supabase.from('recycle_posts').select('id', { count: 'exact', head: true }),
    supabase.from('products').select('id', { count: 'exact', head: true }),
    supabase.from('profiles').select('nickname, points').order('points', { ascending: false }).limit(5),
    supabase.from('products').select('id, name, price, image_after, kind').order('created_at', { ascending: false }).limit(4),
    user.value ? supabase.from('orders').select('id', { count: 'exact', head: true }).eq('buyer', user.value.id)
               : Promise.resolve({ count: 0 }),
  ])
  const posts = p1.count ?? 0
  stats.value = {
    posts,
    products: p2.count ?? 0,
    carbon: (posts * 5).toFixed(1), // 每件回收闲置估算减碳 5kg（宣传口径）
  }
  leaders.value = p3.data ?? []
  latest.value = p4.data ?? []
  orderCount.value = p5.count ?? 0
  // 恢复上次的双人家园状态
  if (localStorage.getItem('home-baby') === '1') setTimeout(() => dormRef.value?.spawnBaby(), 800)
})

onBeforeUnmount(() => window.removeEventListener('dorm-unlock', openBox))

/** 积分等级称号 */
function levelName(points) {
  if (points >= 100) return '🌍 环保大使'
  if (points >= 50) return '🌱 低碳达人'
  if (points >= 20) return '🍃 循环新手'
  return '✨ 见习居民'
}
</script>

<template>
  <div class="max-w-5xl mx-auto px-4 py-6">
    <!-- Hero 标语 -->
    <section class="text-center mb-6">
      <h1 class="text-2xl md:text-4xl font-bold text-mint-700">让闲置醒来，让宿舍焕新 🌿</h1>
      <p class="text-gray-500 mt-2 text-sm md:text-base">校园闲置回收 × DIY 改造 —— 低碳生活，从宿舍开始</p>
    </section>

    <!-- 公益数据统计条 -->
    <section class="grid grid-cols-3 gap-3 mb-6">
      <div class="card !p-3 text-center">
        <p class="text-xl md:text-2xl font-bold text-mint-600">{{ stats.posts }}</p>
        <p class="text-xs text-gray-500 mt-1">回收闲置（件）</p>
      </div>
      <div class="card !p-3 text-center">
        <p class="text-xl md:text-2xl font-bold text-mint-600">{{ stats.products }}</p>
        <p class="text-xs text-gray-500 mt-1">改造好物（件）</p>
      </div>
      <div class="card !p-3 text-center">
        <p class="text-xl md:text-2xl font-bold text-mint-600">{{ stats.carbon }}kg</p>
        <p class="text-xs text-gray-500 mt-1">累计减碳（估算）</p>
      </div>
    </section>

    <!-- 盲盒解锁提示 -->
    <Transition name="fade">
      <div v-if="boxToast" class="fixed top-20 left-1/2 -translate-x-1/2 z-50 bg-mint-600 text-white px-5 py-3 rounded-2xl shadow-lg text-center max-w-[90vw]">
        <p class="text-sm font-bold">🎁 盲盒开启：{{ boxToast.name }}</p>
        <p class="text-xs text-mint-100 mt-0.5">{{ boxToast.desc }}</p>
      </div>
    </Transition>

    <!-- 3D 宿舍家园 + 好友互动面板 -->
    <section class="grid lg:grid-cols-3 gap-4">
      <div class="lg:col-span-2 h-[420px] md:h-[520px]">
        <Dorm3D ref="dormRef" :level="homeLevel" @pick="openZone" />
      </div>

      <!-- 右侧：好友邀请 / 亲密度 / 家园成长 -->
      <aside class="space-y-3">
        <!-- 家园等级 -->
        <div class="card !p-4">
          <div class="flex items-center justify-between">
            <h3 class="font-bold text-mint-700 text-sm">🏠 我的家园</h3>
            <span class="text-[11px] px-2 py-0.5 rounded-full bg-mint-100 text-mint-700">Lv.{{ homeLevel }}</span>
          </div>
          <p class="text-xs text-gray-500 mt-1.5">
            已购买 <b class="text-mint-600">{{ orderCount }}</b> 件二手好物
          </p>
          <div class="mt-2 h-1.5 bg-gray-100 rounded-full overflow-hidden">
            <div class="h-full bg-mint-400 transition-all" :style="{ width: Math.min(100, orderCount / 5 * 100) + '%' }"></div>
          </div>
          <p class="text-[11px] text-gray-400 mt-1.5">
            买 1 件解锁落地灯 · 3 件解锁沙发挂画 · 5 件解锁吊灯抱枕
          </p>
        </div>

        <!-- 好友邀请 -->
        <div class="card !p-4">
          <h3 class="font-bold text-mint-700 text-sm">🤝 双人家园</h3>
          <p class="text-[11px] text-gray-400 mt-1 mb-2">通过「平台转赠」结识的同学，可以邀请来家里一起玩</p>
          <div class="space-y-1.5">
            <button v-for="f in DEMO_FRIENDS" :key="f" @click="invite(f)"
              class="w-full flex items-center justify-between text-xs px-3 py-2 rounded-xl border transition"
              :class="friendName === f ? 'border-mint-500 bg-mint-50 text-mint-700' : 'border-gray-200 text-gray-600 hover:bg-mint-50'">
              <span class="truncate">{{ friendName === f ? '✅ ' : '➕ ' }}{{ f }}</span>
              <span class="text-[10px] text-gray-400 shrink-0">邀请</span>
            </button>
          </div>

          <div class="flex gap-2 mt-3">
            <button class="flex-1 text-xs bg-mint-500 text-white rounded-full py-2 hover:bg-mint-600" @click="playTogether">🎮 一起玩 +10</button>
            <button class="flex-1 text-xs border border-mint-400 text-mint-600 rounded-full py-2 hover:bg-mint-50" @click="playTogether">🐾 逗猫 +10</button>
          </div>

          <!-- 亲密度 -->
          <div class="mt-3">
            <div class="flex justify-between text-[11px] text-gray-500 mb-1">
              <span>与 {{ friendName || '好友' }} 的亲密度</span>
              <span class="text-mint-600 font-medium">{{ intimacy }} / 100</span>
            </div>
            <div class="h-2 bg-gray-100 rounded-full overflow-hidden">
              <div class="h-full bg-gradient-to-r from-mint-300 to-mint-500 transition-all" :style="{ width: Math.min(100, intimacy) + '%' }"></div>
            </div>
            <p class="text-[11px] text-gray-400 mt-1.5">
              {{ hasBaby ? '💕 已解锁「小屋新成员」' : '亲密度满 100 解锁「小屋新成员」彩蛋' }}
            </p>
            <button :disabled="!hasBaby" @click="makeBaby"
              class="mt-2 w-full text-xs rounded-full py-2 transition"
              :class="hasBaby ? 'bg-amber-400 text-white hover:bg-amber-500' : 'bg-gray-100 text-gray-400 cursor-not-allowed'">
              👶 小屋新成员
            </button>
          </div>
        </div>
      </aside>
    </section>

    <p class="text-center text-xs text-gray-400 mt-2">🎁 小彩蛋：在商城提交购买意向后，回到首页会自动解锁一款随机宿舍皮肤</p>

    <!-- 常规导航按钮：3D 不是唯一入口 -->
    <section class="grid grid-cols-1 sm:grid-cols-3 gap-3 mt-6">
      <router-link to="/recycle" class="btn-primary">♻️ 我要回收闲置</router-link>
      <router-link to="/shop" class="btn-ghost">🛒 全部改造商城</router-link>
      <a href="#about" class="btn-ghost">🌱 关于项目</a>
    </section>

    <!-- 最新改造推荐 + 环保积分榜 -->
    <section class="grid md:grid-cols-3 gap-4 mt-8">
      <!-- 最新改造 -->
      <div class="md:col-span-2">
        <div class="flex items-center justify-between mb-3">
          <h2 class="font-bold text-mint-700">🆕 最新上架</h2>
          <router-link to="/shop" class="text-xs text-mint-600 hover:underline">查看全部 →</router-link>
        </div>
        <div class="grid grid-cols-2 gap-3">
          <router-link v-for="p in latest" :key="p.id" to="/shop" class="card !p-3 flex items-center gap-3 hover:-translate-y-0.5 transition">
            <img v-if="p.image_after" :src="p.image_after" class="w-14 h-14 rounded-xl object-cover shrink-0" />
            <div v-else class="w-14 h-14 bg-mint-100 rounded-xl grid place-items-center shrink-0">🌿</div>
            <div class="min-w-0">
              <p class="text-sm font-medium truncate">{{ p.name }}</p>
              <p class="text-mint-600 text-sm font-bold">¥{{ p.price }}</p>
              <p class="text-[10px] text-gray-400">{{ p.kind === 'refurbished' ? '✨ 翻新二手' : '🎨 社团改造' }}</p>
            </div>
          </router-link>
          <p v-if="!latest.length" class="text-sm text-gray-400 col-span-2 text-center py-4">暂无商品</p>
        </div>
      </div>

      <!-- 环保积分排行榜 -->
      <div>
        <h2 class="font-bold text-mint-700 mb-3">🏅 环保积分榜</h2>
        <div class="card space-y-2.5">
          <div v-for="(u, i) in leaders" :key="i" class="flex items-center gap-2.5">
            <span class="w-6 text-center text-sm font-bold"
              :class="i === 0 ? 'text-amber-500' : i === 1 ? 'text-gray-400' : i === 2 ? 'text-amber-700' : 'text-gray-300'">
              {{ ['🥇', '🥈', '🥉'][i] ?? i + 1 }}
            </span>
            <div class="min-w-0 flex-1">
              <p class="text-sm truncate">{{ u.nickname || '神秘同学' }}</p>
              <p class="text-[10px] text-gray-400">{{ levelName(u.points) }}</p>
            </div>
            <span class="text-sm font-bold text-mint-600">{{ u.points }}</span>
          </div>
          <p v-if="!leaders.length" class="text-sm text-gray-400 text-center py-2">虚位以待，投稿闲置即可上榜！</p>
          <p class="text-[11px] text-gray-400 pt-1 border-t border-gray-50">投稿闲置 +10 分 · 购买改造好物 +5 分</p>
        </div>
      </div>
    </section>

    <!-- 平台运营流程（答辩用） -->
    <section class="mt-8">
      <h2 class="font-bold text-mint-700 mb-3">🔄 一件闲置的新生之旅</h2>
      <div class="grid grid-cols-2 md:grid-cols-4 gap-3">
        <div class="card !p-4">
          <p class="text-2xl">📥</p>
          <h3 class="text-sm font-medium mt-1.5">① 汇聚旧货</h3>
          <p class="text-xs text-gray-500 mt-1">同学投稿闲置，或平台线下进货收购</p>
        </div>
        <div class="card !p-4">
          <p class="text-2xl">🔍</p>
          <h3 class="text-sm font-medium mt-1.5">② 管理员筛选</h3>
          <p class="text-xs text-gray-500 mt-1">清洁翻新后直接上架，或开放给社团认领</p>
        </div>
        <div class="card !p-4">
          <p class="text-2xl">🎨</p>
          <h3 class="text-sm font-medium mt-1.5">③ 社团改造</h3>
          <p class="text-xs text-gray-500 mt-1">DIY 社团认领旧货，二次创作成创意好物</p>
        </div>
        <div class="card !p-4">
          <p class="text-2xl">🛒</p>
          <h3 class="text-sm font-medium mt-1.5">④ 焕新上架</h3>
          <p class="text-xs text-gray-500 mt-1">翻新二手与改造成品，一起在商城等你</p>
        </div>
      </div>
    </section>

    <!-- 关于项目 -->
    <section id="about" class="card mt-8">
      <h2 class="font-bold text-mint-700 mb-2">关于项目</h2>
      <p class="text-sm text-gray-600 leading-relaxed">
        「宿舍焕新」是一个校园低碳循环项目：同学们投稿闲置物品，DIY 社团将其改造为宿舍好物并在改造商城展示。
        商城里有两类好物：管理员筛选翻新后的二手物品，以及 DIY 社团改造创作的创意成品。
        你可以点击上方 3D 宿舍中的床、书桌、置物架等区域，查看对应位置的改造灵感与商品。
        本站为演示 Demo，商城仅支持「提交购买意向」，不含真实支付。
      </p>
    </section>
  </div>
</template>
