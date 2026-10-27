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
const dataError = ref(false)
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
  dataError.value = [p1, p2, p3, p4, p5].some(p => p.error)
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
  <div class="page-shell pb-4">
    <section class="home-intro">
      <div>
        <p class="eyebrow mb-5">CAMPUS CIRCULAR LIVING · 校园循环计划</p>
        <h1>旧物的新故事，<br />从你的<span>小空间</span>开始。</h1>
        <p class="intro-copy">回收一件闲置，发现一份改造灵感。<br class="hidden sm:block" />和校园里的创作者一起，让喜欢的生活慢慢发生。</p>
        <div class="flex flex-wrap gap-3 mt-7">
          <router-link to="/shop" class="btn-primary">发现改造好物 <span aria-hidden="true">↗</span></router-link>
          <router-link to="/recycle" class="btn-ghost">投稿我的闲置</router-link>
        </div>
      </div>
      <div class="intro-note">
        <span class="note-index">01 / RENEW YOUR ROOM</span>
        <p>物尽其用。<br />生活常新。</p>
        <span class="note-bottom">从一盏灯、一张椅子开始 ↙</span>
      </div>
    </section>

    <p v-if="dataError" role="status" class="text-xs text-gray-500 mb-4">校园数据暂时无法获取，统计与好物列表待连接恢复后更新。家园互动仍可体验。</p>
    <section class="impact-strip" aria-label="校园循环数据">
      <div><strong>{{ dataError ? '—' : stats.posts }}</strong><span>件闲置重新出发</span></div>
      <div><strong>{{ dataError ? '—' : stats.products }}</strong><span>件好物等待相遇</span></div>
      <div><strong>{{ dataError ? '—' : stats.carbon }}<small> kg</small></strong><span>估算减碳 · 每件回收按 5 kg 计</span></div>
    </section>

    <Transition name="fade">
      <div v-if="boxToast" role="status" class="fixed top-24 left-1/2 -translate-x-1/2 z-50 bg-mint-700 text-white px-5 py-4 rounded-xl shadow-lg text-center w-max max-w-[90vw]">
        <p class="text-sm font-bold">盲盒开启：{{ boxToast.name }}</p>
        <p class="text-xs text-mint-100 mt-1">{{ boxToast.desc }}</p>
      </div>
    </Transition>

    <section class="mt-12" aria-labelledby="room-heading">
      <div class="section-heading">
        <div><p class="eyebrow mb-2">YOUR LITTLE CORNER</p><h2 id="room-heading" class="section-title">把灵感，放进家里</h2></div>
        <p class="text-xs text-gray-500">拖动旋转 · 点击家具发现同区好物</p>
      </div>
      <div class="room-layout">
        <div class="room-stage"><Dorm3D ref="dormRef" :level="homeLevel" @pick="openZone" /></div>
        <aside class="room-panel">
          <div class="flex items-center justify-between"><p class="eyebrow">MY DORM</p><span class="level-label">Lv.{{ homeLevel }}</span></div>
          <h3 class="text-2xl font-semibold mt-3">我的焕新家园</h3>
          <p class="text-xs text-gray-500 mt-2 leading-6">已提交 {{ orderCount }} 件好物的购买意向<br />每一次循环，都让小屋多一点温度。</p>
          <div class="mt-4 h-1 bg-[#e1e5da] overflow-hidden"><div class="h-full bg-mint-600" :style="{ width: Math.min(100, orderCount / 5 * 100) + '%' }"></div></div>
          <p class="text-[11px] text-gray-500 mt-2 leading-5">1 件 · 落地灯 / 3 件 · 沙发挂画 / 5 件 · 吊灯抱枕</p>
          <div class="panel-divider"></div>
          <div class="flex justify-between items-center"><h3 class="text-sm font-semibold">邀请伙伴来坐坐</h3><span class="text-[10px] text-gray-500">演示互动</span></div>
          <div class="space-y-2 mt-3">
            <button v-for="f in DEMO_FRIENDS" :key="f" @click="invite(f)" class="friend-button" :class="{ selected: friendName === f }">
              <span>{{ f }}</span><span>{{ friendName === f ? '已邀请 ✓' : '邀请 ↗' }}</span>
            </button>
          </div>
          <div class="flex gap-2 mt-3">
            <button class="btn-primary flex-1 !px-2 !py-2.5 !text-xs" @click="playTogether">一起玩 +10</button>
            <button class="btn-ghost flex-1 !px-2 !py-2.5 !text-xs" @click="playTogether">逗猫 +10</button>
          </div>
          <div class="flex justify-between text-[11px] text-gray-500 mt-4"><span>伙伴亲密度</span><span>{{ intimacy }} / 100</span></div>
          <div class="mt-2 h-1 bg-[#e1e5da]"><div class="h-full bg-[#bd8d60]" :style="{ width: Math.min(100, intimacy) + '%' }"></div></div>
          <button :disabled="!hasBaby" @click="makeBaby" class="mt-3 text-xs text-mint-700 underline underline-offset-4">{{ hasBaby ? '迎接小屋新成员 ↗' : '亲密度满 100，解锁小屋新成员' }}</button>
        </aside>
      </div>
      <p class="text-xs text-gray-500 mt-3">家园彩蛋 / 在商城提交购买意向后，回到这里开启一款随机宿舍风格。</p>
    </section>

    <section class="mt-14 grid md:grid-cols-3 gap-8">
      <div class="md:col-span-2">
        <div class="section-heading"><div><p class="eyebrow mb-2">FRESH FINDS</p><h2 class="section-title">新近焕新</h2></div><router-link to="/shop" class="text-xs text-mint-700">浏览全部 ↗</router-link></div>
        <div class="grid grid-cols-2 gap-4">
          <router-link v-for="p in latest" :key="p.id" to="/shop" class="latest-card">
            <img v-if="p.image_after" :src="p.image_after" :alt="p.name" loading="lazy" />
            <div v-else class="latest-placeholder"><span>RE / NEW</span></div>
            <div class="flex justify-between items-start gap-2 mt-3"><h3 class="text-sm font-medium truncate">{{ p.name }}</h3><span class="text-sm font-semibold">¥{{ p.price }}</span></div>
            <p class="text-[11px] text-gray-500 mt-1">{{ p.kind === 'refurbished' ? '翻新二手' : '社团改造' }}</p>
          </router-link>
          <p v-if="!latest.length" class="empty-state col-span-2">好物正在准备中。<router-link to="/recycle" class="underline">投稿一件闲置</router-link>，开启它的新故事。</p>
        </div>
      </div>
      <div>
        <div class="section-heading"><div><p class="eyebrow mb-2">SMALL ACTIONS, REAL IMPACT</p><h2 class="section-title">校园循环伙伴</h2></div></div>
        <div class="leaderboard">
          <div v-for="(u, i) in leaders" :key="i" class="leader-row">
            <span class="rank-number">{{ String(i + 1).padStart(2, '0') }}</span>
            <div class="min-w-0 flex-1"><p class="text-sm truncate">{{ u.nickname || '神秘同学' }}</p><p class="text-[10px] text-gray-500 mt-1">{{ levelName(u.points) }}</p></div>
            <strong class="text-sm">{{ u.points }}<small class="font-normal ml-1 text-gray-500">分</small></strong>
          </div>
          <p v-if="!leaders.length" class="text-sm text-gray-500 py-6">第一位循环伙伴，虚位以待。</p>
          <p class="text-[11px] text-gray-500 border-t border-[#e1e5da] pt-4 mt-2">投稿 +10 分 · 购买意向 +5 分</p>
        </div>
      </div>
    </section>

    <section id="about" class="journey-section">
      <div class="section-heading"><div><p class="eyebrow mb-2">THE SECOND CHAPTER</p><h2 class="section-title">一件闲置的新生之旅</h2></div><span class="text-xs text-gray-500">从你的宿舍，到另一个人的日常</span></div>
      <div class="journey-grid">
        <div v-for="(step, i) in [{ title: '汇聚闲置', copy: '拍下不再使用的物品，让它被重新看见。' }, { title: '用心筛选', copy: '管理员检查物品，选择翻新或社团改造。' }, { title: '赋予新意', copy: '校园 DIY 创作者动手，为旧物添一份巧思。' }, { title: '继续被喜欢', copy: '带回一件焕新好物，让循环融入日常。' }]" :key="step.title">
          <span class="eyebrow">0{{ i + 1 }} <span class="float-right" aria-hidden="true">↗</span></span><h3 class="text-base font-semibold mt-5">{{ step.title }}</h3><p class="text-xs text-gray-500 leading-6 mt-2">{{ step.copy }}</p>
        </div>
      </div>
      <p class="text-[11px] text-gray-500 mt-6 leading-6">「宿舍焕新」连接校园闲置回收与 DIY 改造。本项目为国创赛演示，商城仅收集购买意向，不含真实支付。好友与家园亲密度为本机演示数据。</p>
    </section>
    <ProductDrawer :visible="drawerVisible" :zone-key="zoneKey" :zone-label="zoneLabel" @close="drawerVisible = false" />
  </div>
</template>

<style scoped>
.home-intro { display: grid; grid-template-columns: 1fr 260px; align-items: center; gap: 56px; padding: 60px 0 44px; }
.home-intro h1 { font-size: clamp(32px, 4vw, 52px); line-height: 1.35; font-weight: 600; letter-spacing: -.055em; }
.home-intro h1 span { color: #567b58; }
.intro-copy { font-size: 13px; line-height: 1.9; color: #7a8379; margin-top: 20px; }
.intro-note { align-self: stretch; border-radius: 140px 140px 8px 8px; background: #e5e9db; padding: 60px 28px 26px; display: flex; flex-direction: column; justify-content: space-between; position: relative; }
.intro-note::after { content: ''; position: absolute; width: 80px; height: 80px; border: 1px solid #bac7ae; border-radius: 50%; top: 22px; right: 30px; }
.note-index { font-size: 8px; letter-spacing: .1em; color: #7f8c70; }
.intro-note p { font-size: 30px; font-weight: 300; line-height: 1.6; margin: 18px 0; }
.note-bottom { font-size: 10px; color: #718476; }
.impact-strip { display: grid; grid-template-columns: repeat(3, 1fr); border-top: 1px solid #d9dfd3; border-bottom: 1px solid #d9dfd3; padding: 25px 0; }
.impact-strip > div { display: flex; align-items: center; gap: 18px; padding: 0 24px; border-right: 1px solid #d9dfd3; }
.impact-strip > div:first-child { padding-left: 0; }
.impact-strip > div:last-child { border: 0; }
.impact-strip strong { font-size: 30px; letter-spacing: -.06em; font-weight: 500; white-space: nowrap; }
.impact-strip small { font-size: 14px; }
.impact-strip span { font-size: 11px; color: #7a8379; }
.section-heading { display: flex; flex-wrap: wrap; gap: 16px; justify-content: space-between; align-items: end; margin-bottom: 22px; }
.room-layout { display: grid; grid-template-columns: minmax(0, 1fr) 300px; border: 1px solid #dce2d4; border-radius: 18px; overflow: hidden; background: #edf0e5; }
.room-stage { height: 560px; min-width: 0; }
.room-panel { padding: 30px 24px; background: #f0f1e8; border-left: 1px solid #dce2d4; }
.level-label { font-size: 11px; border: 1px solid #bdcbb5; padding: 3px 8px; border-radius: 4px; }
.panel-divider { border-top: 1px solid #d9dfd3; margin: 24px 0; }
.friend-button { display: flex; justify-content: space-between; align-items: center; gap: 8px; width: 100%; font-size: 11px; border: 1px solid #d2dacb; padding: 11px; border-radius: 6px; text-align: left; }
.friend-button.selected { background: #e0e8d8; border-color: #829a79; }
.latest-card { padding-bottom: 12px; }
.latest-card img, .latest-placeholder { width: 100%; height: 180px; object-fit: cover; border-radius: 10px; background: #e9ebdf; transition: filter .2s; }
.latest-card:hover img { filter: brightness(.96); }
.latest-placeholder { display: grid; place-items: center; color: #9aa88f; font-size: 18px; letter-spacing: .25em; }
.leaderboard { padding: 8px 22px 22px; background: #edeee5; border-radius: 12px; }
.leader-row { display: flex; align-items: center; gap: 14px; padding: 14px 0; }
.rank-number { color: #97a188; font-size: 18px; font-weight: 300; }
.journey-section { border-top: 1px solid #d9dfd3; margin-top: 56px; padding-top: 34px; }
.journey-grid { display: grid; grid-template-columns: repeat(4, 1fr); gap: 28px; }
.journey-grid > div { border-top: 1px solid #bfcab8; padding-top: 16px; }
@media(max-width: 900px) {
  .room-layout { grid-template-columns: 1fr; }
  .room-panel { border-left: 0; border-top: 1px solid #dce2d4; }
  .impact-strip > div { flex-direction: column; align-items: start; gap: 4px; }
}
@media(max-width: 640px) {
  .home-intro { grid-template-columns: 1fr; padding-top: 38px; gap: 24px; }
  .intro-note { display: none; }
  .impact-strip > div { padding: 0 10px; }
  .impact-strip strong { font-size: 26px; }
  .impact-strip span { font-size: 10px; line-height: 1.7; }
  .room-stage { height: 440px; }
  .journey-grid { grid-template-columns: repeat(2, 1fr); gap: 24px; }
  .latest-card img, .latest-placeholder { height: 145px; }
}
</style>
