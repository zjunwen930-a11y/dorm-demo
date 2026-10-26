<script setup>
/**
 * 个人中心 v2 —— 角色展示 / 碳积分与等级 / 我的投稿 / 我的收藏 / 我的购买意向
 */
import { ref, onMounted } from 'vue'
import { supabase } from '../lib/supabase'
import { useAuth } from '../stores/auth'
import { useRouter } from 'vue-router'

const { user, role, signOut } = useAuth()
const router = useRouter()

const ROLE_TEXT = { student: '普通学生', member: 'DIY 社团成员', admin: '管理员' }
const myPosts = ref([])
const myOrders = ref([])
const myFavs = ref([])     // 我的收藏（含商品信息）

// 等级称号
const levelName = (pts) => pts >= 100 ? '🌍 环保大使' : pts >= 50 ? '🌱 低碳达人' : pts >= 20 ? '🍃 循环新手' : '✨ 见习居民'
// 距下一等级还差多少分
const nextLevelGap = (pts) => pts >= 100 ? '已达最高等级' : `还差 ${Math.ceil((pts >= 50 ? 100 : pts >= 20 ? 50 : 20) - pts)} 分升级`

onMounted(async () => {
  const [p, o, f] = await Promise.all([
    supabase.from('recycle_posts').select('*').eq('author', user.value.id).order('created_at', { ascending: false }),
    supabase.from('orders').select('*, products(name, price)').eq('buyer', user.value.id).order('created_at', { ascending: false }),
    // 我的收藏：联表取商品名称和价格
    supabase.from('favorites').select('product_id, created_at, products(name, price, image_after)').eq('user_id', user.value.id).order('created_at', { ascending: false }),
  ])
  myPosts.value = p.data ?? []
  myOrders.value = o.data ?? []
  myFavs.value = f.data ?? []
})

async function logout() {
  await signOut()
  router.push('/')
}
</script>

<template>
  <div class="max-w-xl mx-auto px-4 py-8 space-y-5">
    <!-- 用户信息 + 碳积分卡 -->
    <section class="card">
      <div class="flex items-center gap-4">
        <div class="w-14 h-14 rounded-full bg-mint-200 grid place-items-center text-2xl">🌿</div>
        <div class="flex-1 min-w-0">
          <p class="font-bold truncate">{{ user.email }}</p>
          <span class="text-xs bg-mint-100 text-mint-700 px-2.5 py-1 rounded-full mt-1 inline-block">
            当前角色：{{ ROLE_TEXT[role] ?? '读取中…' }}
          </span>
        </div>
        <button class="text-xs border border-red-200 text-red-500 rounded-full px-4 py-2 hover:bg-red-50 transition" @click="logout">退出登录</button>
      </div>
      <!-- 积分进度 -->
      <div class="mt-4 bg-mint-50 rounded-2xl p-4">
        <div class="flex items-end justify-between">
          <div>
            <p class="text-xs text-gray-500">我的碳积分</p>
            <p class="text-2xl font-bold text-mint-600 leading-tight">{{ myPosts.length * 10 + myOrders.length * 5 }} <span class="text-sm font-normal text-gray-400">分</span></p>
          </div>
          <span class="text-sm font-medium text-mint-700">{{ levelName(myPosts.length * 10 + myOrders.length * 5) }}</span>
        </div>
        <p class="text-[11px] text-gray-400 mt-1.5">{{ nextLevelGap(myPosts.length * 10 + myOrders.length * 5) }} · 投稿闲置 +10 分 / 购买好物 +5 分</p>
      </div>
    </section>

    <!-- 我的投稿 -->
    <section class="card">
      <h2 class="font-medium text-mint-700 mb-3">♻️ 我的投稿（{{ myPosts.length }}）</h2>
      <div v-for="p in myPosts" :key="p.id" class="flex justify-between items-center py-2 border-b border-gray-50 last:border-0">
        <span class="text-sm truncate">{{ p.title }}</span>
        <span class="text-xs px-2 py-0.5 rounded-full shrink-0"
          :class="p.status === 'pending' ? 'bg-amber-100 text-amber-600' : p.status === 'claimed' ? 'bg-blue-100 text-blue-600' : 'bg-mint-100 text-mint-700'">
          {{ { pending: '审核中', claimed: '已进入改造池', done: '已上架' }[p.status] }}
        </span>
      </div>
      <p v-if="!myPosts.length" class="text-sm text-gray-400">还没有投稿，去 <router-link class="text-mint-600" to="/recycle">闲置回收</router-link> 试试吧</p>
    </section>

    <!-- 我的收藏 -->
    <section class="card">
      <h2 class="font-medium text-mint-700 mb-3">❤️ 我的收藏（{{ myFavs.length }}）</h2>
      <div v-for="f in myFavs" :key="f.product_id" class="flex items-center gap-3 py-2 border-b border-gray-50 last:border-0">
        <img v-if="f.products?.image_after" :src="f.products.image_after" class="w-10 h-10 rounded-lg object-cover" />
        <div v-else class="w-10 h-10 bg-mint-50 rounded-lg grid place-items-center">🌿</div>
        <span class="text-sm flex-1 truncate">{{ f.products?.name }}</span>
        <span class="text-sm text-mint-600 font-bold">¥{{ f.products?.price }}</span>
        <router-link to="/shop" class="text-xs text-mint-600 hover:underline">去下单</router-link>
      </div>
      <p v-if="!myFavs.length" class="text-sm text-gray-400">逛逛 <router-link class="text-mint-600" to="/shop">改造商城</router-link>，收藏喜欢的好物吧</p>
    </section>

    <!-- 我的购买意向 -->
    <section class="card">
      <h2 class="font-medium text-mint-700 mb-3">🛒 我的购买意向（{{ myOrders.length }}）</h2>
      <div v-for="o in myOrders" :key="o.id" class="flex justify-between py-2 border-b border-gray-50 last:border-0">
        <span class="text-sm">{{ o.products?.name }}</span>
        <span class="text-sm text-mint-600">¥{{ o.products?.price }}</span>
      </div>
      <p v-if="!myOrders.length" class="text-sm text-gray-400">暂无购买意向</p>
    </section>
  </div>
</template>
