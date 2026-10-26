<script setup>
/**
 * ProductDrawer —— 侧边滑层商品展示
 * 点击 3D 热区后从右侧（移动端从底部）滑出，展示对应分区的改造商品。
 */
import { supabase } from '../lib/supabase'
import { useAuth } from '../stores/auth'

const props = defineProps({
  visible: Boolean,   // 是否显示
  zoneKey: String,    // 分区 key（bed/desk/nightstand/shelf/floor）
  zoneLabel: String,  // 分区中文名
})
const emit = defineEmits(['close'])

const { user } = useAuth()
const products = ref([])
const loading = ref(false)
const tip = ref('')

// 分区变化或打开时 → 从 Supabase 拉取该分区商品
watch(() => [props.visible, props.zoneKey], async ([v]) => {
  if (!v || !props.zoneKey) return
  loading.value = true
  const { data } = await supabase
    .from('products')
    .select('*')
    .eq('zone', props.zoneKey)
    .order('created_at', { ascending: false })
  products.value = data ?? []
  loading.value = false
})

/** 提交购买意向（不涉及真实支付） */
async function buy(p) {
  if (!user.value) { tip.value = '请先登录再提交购买意向'; return }
  const { error } = await supabase.from('orders').insert({
    product_id: p.id,
    buyer: user.value.id,
  })
  if (error) {
    tip.value = error.message.includes('policy') ? '提交失败（权限不足）' : '提交失败：' + error.message
    return
  }
  tip.value = `已提交「${p.name}」的购买意向 ✓ 🎁 已解锁一次宿舍盲盒`
  localStorage.setItem('dorm-pending-box', '1')
  window.dispatchEvent(new Event('dorm-unlock'))
  if (!error) setTimeout(() => emit('close'), 1400)
}
</script>

<template>
  <!-- 遮罩 -->
  <Transition name="fade">
    <div v-if="visible" class="fixed inset-0 bg-black/30 z-50" @click="emit('close')" />
  </Transition>

  <!-- 滑层：桌面端右侧抽屉，移动端底部弹层 -->
  <Transition name="slide">
    <aside v-if="visible"
      class="fixed z-50 bg-cream shadow-2xl overflow-y-auto
             inset-x-0 bottom-0 max-h-[75vh] rounded-t-3xl
             md:inset-y-0 md:right-0 md:left-auto md:w-[420px] md:max-h-none md:rounded-none md:rounded-l-3xl">
      <header class="sticky top-0 bg-cream/95 backdrop-blur flex items-center justify-between px-5 py-4 border-b border-mint-100">
        <h3 class="font-bold text-mint-700 text-lg">🛠️ {{ zoneLabel }} · 改造灵感</h3>
        <button class="text-gray-400 hover:text-gray-600 text-xl leading-none" @click="emit('close')">✕</button>
      </header>

      <p v-if="tip" class="mx-5 mt-3 text-sm bg-mint-100 text-mint-700 rounded-xl px-4 py-2.5">{{ tip }}</p>

      <div v-if="loading" class="p-8 text-center text-gray-400">加载中…</div>
      <div v-else-if="!products.length" class="p-8 text-center text-gray-400">该分区暂无改造商品，敬请期待 🌱</div>

      <!-- 商品卡片：改造前后对比图 + 设计理念 + 价格 -->
      <div v-else class="p-4 space-y-4">
        <article v-for="p in products" :key="p.id" class="card">
          <div class="flex gap-3">
            <!-- 改造前 / 改造后 对比图 -->
            <div class="flex gap-1.5 shrink-0">
              <div class="w-20">
                <img v-if="p.image_before" :src="p.image_before" class="w-20 h-20 object-cover rounded-lg" />
                <div v-else class="w-20 h-20 bg-gray-100 rounded-lg grid place-items-center text-[10px] text-gray-400">改造前</div>
                <p class="text-[10px] text-center text-gray-400 mt-1">改造前</p>
              </div>
              <div class="w-20">
                <img v-if="p.image_after" :src="p.image_after" class="w-20 h-20 object-cover rounded-lg" />
                <div v-else class="w-20 h-20 bg-mint-100 rounded-lg grid place-items-center text-[10px] text-mint-500">改造后</div>
                <p class="text-[10px] text-center text-gray-400 mt-1">改造后</p>
              </div>
            </div>
            <div class="min-w-0 flex-1">
              <h4 class="font-medium text-gray-800 truncate">{{ p.name }}</h4>
              <p class="text-xs text-gray-500 mt-1 line-clamp-2">{{ p.description }}</p>
              <div class="flex items-center justify-between mt-2">
                <span class="text-mint-600 font-bold">¥{{ p.price }}</span>
                <button class="text-xs bg-mint-500 text-white px-3 py-1.5 rounded-full hover:bg-mint-600" @click="buy(p)">
                  提交购买意向
                </button>
              </div>
            </div>
          </div>
        </article>
      </div>
    </aside>
  </Transition>
</template>

<style scoped>
.fade-enter-active,.fade-leave-active{transition:opacity .25s}
.fade-enter-from,.fade-leave-to{opacity:0}
.slide-enter-active,.slide-leave-active{transition:transform .3s ease}
.slide-enter-from,.slide-leave-to{transform:translateY(100%)}
@media (min-width:768px){
  .slide-enter-from,.slide-leave-to{transform:translateX(100%)}
}
</style>
