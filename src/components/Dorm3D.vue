<script setup>
/**
 * Dorm3D v6 —— 宿舍家园系统（演示版）
 * -------------------------------------------------
 * 组成：精致房间 + Q版小人（会自己看书/玩电脑/画画/睡觉）+ 猫狗 + 好友小人 + 宝宝
 * 成长：购买件数越多，解锁越精致的家具（Lv.1 落地灯 / Lv.2 沙发挂画 / Lv.3 吊灯抱枕）
 * 互动：inviteFriend(name) 邀请好友、playTogether() 一起玩、spawnBaby() 小屋新成员
 */
import { onMounted, onBeforeUnmount, ref, watch } from 'vue'
import * as THREE from 'three'
import { OrbitControls } from 'three/examples/jsm/controls/OrbitControls.js'
import { createAvatar } from '../three/avatar'
import { createPet } from '../three/pet'

const props = defineProps({
  level: { type: Number, default: 0 },   // 家园等级（由购买件数决定）
})
const emit = defineEmits(['pick'])

const container = ref(null)
const activeZone = ref(null)
const themeIndex = ref(0)
const activityText = ref('在家里发呆')     // 当前小人状态（给 UI 显示）

let renderer, scene, camera, controls, raycaster, pointer
let rafId
const disposables = []
let hitTargets = []
let zoneMarkers = []
const R = { wood: [], frame: [] }
let decorGroup = null
let luxGroups = { lv1: null, lv2: null, lv3: null }
let particles = []

// 角色 / 宠物
let me, friend, baby
let cat, dog
let clockT = 0
let activity = 'idle'
let nextActivityAt = 6
let playingUntil = 0

/* ================= 6 套盲盒风格 ================= */
const THEMES = [
  {
    name: '薄荷清新 🌿', desc: '原木 + 薄荷绿，治愈系标配',
    bg: '#e7f4ec', fog: '#e7f4ec', wall: '#f2f7f0', floor: '#f6ecd8', ground: '#a9d9a2',
    quilt: '#8fd0ae', pillow: '#ffffff', wood: '#c9a06a', sun: '#fff2dd', sunPower: 1.0, paper: '#ffffff',
    rug: { shape: 'circle', color: '#f6d9c8' },
    decor: { plants: 2, fairy: false, posters: 1, curtain: false, lantern: false, neon: false, laptop: true, books: true, cup: false },
  },
  {
    name: '暖阳米杏 ☀️', desc: '午后阳光洒进来，藤编与小台灯',
    bg: '#fbf1e2', fog: '#fbf1e2', wall: '#fdf6ea', floor: '#f0dcbb', ground: '#cfd9a0',
    quilt: '#f2c48d', pillow: '#fff8ee', wood: '#d3a86e', sun: '#ffd7a0', sunPower: 1.15, paper: '#fffaf0',
    rug: { shape: 'rect', color: '#e8d3b5' },
    decor: { plants: 3, fairy: false, posters: 2, curtain: true, lantern: true, neon: false, laptop: false, books: true, cup: true },
  },
  {
    name: '樱粉少女 🌸', desc: '粉雾墙 + 星星灯串 + 花边窗帘',
    bg: '#fdeef2', fog: '#fdeef2', wall: '#fdf3f5', floor: '#f3e2e4', ground: '#dcc0cd',
    quilt: '#f3b7c8', pillow: '#fff2f5', wood: '#e0b7b7', sun: '#ffe3ec', sunPower: 1.05, paper: '#ffeef3',
    rug: { shape: 'circle', color: '#f7dbe4' },
    decor: { plants: 2, fairy: true, posters: 2, curtain: true, lantern: false, neon: false, laptop: false, books: true, cup: true },
  },
  {
    name: '夜蓝霓虹 🌙', desc: '关灯后的宿舍，霓虹灯带与星空',
    bg: '#1e2333', fog: '#1e2333', wall: '#2b3350', floor: '#39415c', ground: '#161a26',
    quilt: '#7f8fc9', pillow: '#c9d5f2', wood: '#5c6480', sun: '#a9c4ff', sunPower: 0.55, paper: '#e8eeff',
    rug: { shape: 'circle', color: '#39456b' },
    decor: { plants: 1, fairy: true, posters: 2, curtain: false, lantern: false, neon: true, laptop: true, books: true, cup: false },
  },
  {
    name: '森野绿意 🍃', desc: '满屋绿植，木质地板与纸灯笼',
    bg: '#e7f1e4', fog: '#e7f1e4', wall: '#eef5ea', floor: '#e0d3b4', ground: '#9cc98f',
    quilt: '#a8cf9a', pillow: '#f6fff2', wood: '#b98f5e', sun: '#f2ffe0', sunPower: 0.95, paper: '#f7ffe9',
    rug: { shape: 'rect', color: '#dfe4c8' },
    decor: { plants: 5, fairy: false, posters: 1, curtain: true, lantern: true, neon: false, laptop: false, books: true, cup: false },
  },
  {
    name: '复古木质 🪵', desc: '深色木纹、方格地毯与旧书堆',
    bg: '#f2e7d5', fog: '#f2e7d5', wall: '#efe0c8', floor: '#c9a06a', ground: '#b8a37a',
    quilt: '#d98f5f', pillow: '#f5e3c8', wood: '#8b5e3c', sun: '#ffcf94', sunPower: 1.0, paper: '#fdf1e0',
    rug: { shape: 'rect', color: '#b5654a' },
    decor: { plants: 2, fairy: true, posters: 3, curtain: true, lantern: false, neon: false, laptop: false, books: true, cup: true },
  },
]

/* ================= 热区 ================= */
const ZONES = [
  { key: 'bed',        label: '床区域',     pos: [-1.1, 0.6, -1.2], box: [1.7, 1.2, 2.7],  center: [-1.6, 0.85, -1.6] },
  { key: 'desk',       label: '书桌',       pos: [1.3, 0.95, -1.3], box: [1.9, 1.3, 1.1],  center: [1.6, 0.9, -1.9] },
  { key: 'nightstand', label: '床头柜',     pos: [-1.2, 0.5, 0.1],  box: [0.95, 1.3, 0.85], center: [-1.6, 0.9, 0.2] },
  { key: 'shelf',      label: '置物架',     pos: [1.5, 1.1, 0.8],   box: [0.9, 2.1, 1.1],   center: [2.2, 1.25, -0.5] },
  { key: 'floor',      label: '地面收纳区', pos: [0, 0.25, 1.1],    box: [1.9, 1.0, 1.3],   center: [0.2, 0.75, 1.6] },
]

/* ================= 小人活动锚点 ================= */
const ANCHORS = {
  idle:   { pos: [-0.55, 0.25, 0.75], rotY: 0.55, rotZ: 0,    action: 'idle',  text: '在家里发呆' },
  read:   { pos: [0.15, 0.28, 1.95],  rotY: 0.25, rotZ: 0,    action: 'read',  text: '坐在地毯上看书' },
  draw:   { pos: [-0.9, 0.28, 1.55],  rotY: 1.1,  rotZ: 0,    action: 'draw',  text: '趴在地上画画' },
  pc:     { pos: [1.32, 0.63, -1.12], rotY: Math.PI, rotZ: 0, action: 'pc',    text: '在书桌玩电脑' },
  sleep:  { pos: [-1.55, 0.92, -1.5], rotY: 0, rotZ: Math.PI / 2, action: 'sleep', text: '在床上睡觉' },
  friend: { pos: [-1.55, 0.25, 2.05], rotY: 0.95, rotZ: 0,    action: 'idle',  text: '好友在等你' },
  playA:  { pos: [0.85, 0.3, 1.95],   rotY: 1.5,  rotZ: 0,    action: 'dance', text: '和好友一起玩' },
  playB:  { pos: [-0.35, 0.3, 2.1],   rotY: 2.3,  rotZ: 0,    action: 'dance', text: '和好友一起玩' },
}

const M = (color) => new THREE.MeshLambertMaterial({ color })
const EM = (color, intensity = 0.9) => new THREE.MeshLambertMaterial({ color, emissive: color, emissiveIntensity: intensity })

function box(w, h, d, color, x, y, z, parent, cast = true) {
  const g = new THREE.BoxGeometry(w, h, d); const mat = M(color)
  const m = new THREE.Mesh(g, mat); m.position.set(x, y, z)
  m.castShadow = cast; m.receiveShadow = cast
  ;(parent || scene).add(m); disposables.push(g, mat); return m
}

/* ================= 房间（含精修细节） ================= */
let sunLight
function buildRoom() {
  scene = new THREE.Scene()
  scene.background = new THREE.Color(THEMES[0].bg)
  scene.fog = new THREE.Fog(THEMES[0].fog, 15, 30)

  camera = new THREE.PerspectiveCamera(42, container.value.clientWidth / container.value.clientHeight, 0.1, 100)
  camera.position.set(5.2, 4.4, 6.8)

  scene.add(new THREE.AmbientLight('#ffffff', 0.56))
  sunLight = new THREE.DirectionalLight('#fff2dd', 1.0)
  sunLight.position.set(6, 9, 4); sunLight.castShadow = true
  sunLight.shadow.mapSize.set(1024, 1024)
  sunLight.shadow.camera.left = -8; sunLight.shadow.camera.right = 8
  sunLight.shadow.camera.top = 8; sunLight.shadow.camera.bottom = -8
  sunLight.shadow.radius = 4
  scene.add(sunLight)
  scene.add(new THREE.HemisphereLight('#dff3e6', '#c8b89a', 0.5))

  // 草地
  const ground = box(14, 0.3, 14, THEMES[0].ground, 0, -0.15, 0)
  ground.receiveShadow = true; R.ground = ground.material

  // 地板 + 墙
  const floor = box(7, 0.25, 6, THEMES[0].floor, 0, 0.125, 0); R.floor = floor.material
  R.wallA = box(7, 3.2, 0.25, THEMES[0].wall, 0, 1.72, -3).material
  R.wallB = box(0.25, 3.2, 6, THEMES[0].wall, -3.5, 1.72, 0).material
  box(7, 0.18, 6, '#ffffff', 0, 3.35, 0)

  // 地板拼缝（细节）
  for (let i = -2; i <= 2; i++) {
    box(6.9, 0.02, 0.03, '#e8dcc4', 0, 0.26, i * 1.1, null, false)
  }
  // 踢脚线
  box(6.9, 0.14, 0.05, '#f7f2e8', 0, 0.32, -2.86, null, false)
  box(0.05, 0.14, 5.9, '#f7f2e8', -3.36, 0.32, 0, null, false)

  // 窗户 + 窗台
  R.glass = box(1.6, 1.2, 0.06, '#bfe3f2', -0.6, 2.0, -2.86, null, false).material
  R.frame = [
    box(1.8, 0.12, 0.1, '#ffffff', -0.6, 2.64, -2.84, null, false).material,
    box(1.8, 0.12, 0.1, '#ffffff', -0.6, 1.36, -2.84, null, false).material,
    box(0.12, 1.3, 0.1, '#ffffff', -1.43, 2.0, -2.84, null, false).material,
    box(0.12, 1.3, 0.1, '#ffffff', 0.23, 2.0, -2.84, null, false).material,
  ]
  box(2.0, 0.08, 0.24, '#ffffff', -0.6, 1.3, -2.78, null, false)

  // 挂钟
  const clockG = new THREE.CylinderGeometry(0.19, 0.19, 0.05, 20)
  const clockM = M('#ffffff')
  const clock = new THREE.Mesh(clockG, clockM)
  clock.rotation.x = Math.PI / 2
  clock.position.set(2.55, 2.45, -2.86)
  scene.add(clock)
  const handG = new THREE.BoxGeometry(0.015, 0.12, 0.01)
  const h1 = new THREE.Mesh(handG, M('#666666')); h1.position.set(2.55, 2.49, -2.83)
  const h2 = new THREE.Mesh(new THREE.BoxGeometry(0.015, 0.08, 0.01), M('#999999'))
  h2.position.set(2.58, 2.45, -2.83); h2.rotation.z = -1.2
  scene.add(h1, h2)

  // 吸顶灯
  const shadeG = new THREE.CylinderGeometry(0.34, 0.26, 0.14, 18)
  const shade = new THREE.Mesh(shadeG, M('#fdfdfd'))
  shade.position.set(0.2, 3.2, 0.2); scene.add(shade)
  const bulb = new THREE.Mesh(new THREE.SphereGeometry(0.1, 12, 10), EM('#fff6d8', 1.2))
  bulb.position.set(0.2, 3.1, 0.2); scene.add(bulb)

  // 门（左墙）
  box(0.06, 1.9, 1.0, '#e8dcc4', -3.45, 1.1, 1.6, null, false)
  const knob = new THREE.Mesh(new THREE.SphereGeometry(0.05, 10, 10), M('#c9a06a'))
  knob.position.set(-3.4, 1.1, 2.0); scene.add(knob)

  // 床
  const bed = new THREE.Group()
  R.wood.push(box(1.4, 0.35, 2.4, '#c9a06a', 0, 0.18, 0, bed).material)
  box(1.3, 0.22, 2.2, '#fdfdf6', 0, 0.47, 0, bed)
  R.quilt = box(1.1, 0.18, 1.4, THEMES[0].quilt, 0, 0.62, 0.35, bed).material
  // 被子褶皱
  box(1.12, 0.02, 0.05, '#ffffff', 0, 0.72, 0.1, bed, false)
  box(1.12, 0.02, 0.05, '#ffffff', 0, 0.72, 0.55, bed, false)
  R.pillow = box(1.0, 0.16, 0.45, '#ffffff', 0, 0.6, -0.8, bed).material
  bed.position.set(-1.6, 0.25, -1.6); scene.add(bed)

  // 书桌 + 椅子
  const desk = new THREE.Group()
  R.wood.push(box(1.6, 0.1, 0.8, '#d8b98a', 0, 0.85, 0, desk).material)
  R.wood.push(box(0.1, 0.85, 0.7, '#c9a06a', -0.72, 0.43, 0, desk).material)
  R.wood.push(box(0.1, 0.85, 0.7, '#c9a06a', 0.72, 0.43, 0, desk).material)
  desk.position.set(1.6, 0.25, -1.9); scene.add(desk)
  // 椅子
  const chair = new THREE.Group()
  R.wood.push(box(0.44, 0.06, 0.42, '#d8b98a', 0, 0.42, 0, chair).material)
  box(0.06, 0.42, 0.06, '#c9a06a', -0.16, 0.21, 0.16, chair)
  box(0.06, 0.42, 0.06, '#c9a06a', 0.16, 0.21, 0.16, chair)
  box(0.06, 0.42, 0.06, '#c9a06a', -0.16, 0.21, -0.16, chair)
  box(0.06, 0.42, 0.06, '#c9a06a', 0.16, 0.21, -0.16, chair)
  box(0.42, 0.4, 0.05, '#d8b98a', 0, 0.62, 0.19, chair)
  chair.position.set(1.32, 0.25, -1.1); scene.add(chair)

  // 床头柜 + 台灯
  const ns = new THREE.Group()
  R.wood.push(box(0.7, 0.55, 0.6, '#e8cfa5', 0, 0.28, 0, ns).material)
  box(0.5, 0.16, 0.05, '#c9a06a', 0, 0.3, 0.31, ns)
  box(0.04, 0.3, 0.04, '#888888', -0.15, 0.7, 0, ns)
  R.lampM = new THREE.MeshLambertMaterial({ color: '#ffe9a8', emissive: '#ffdf8a', emissiveIntensity: 0.55 })
  const lamp = new THREE.Mesh(new THREE.BoxGeometry(0.26, 0.16, 0.26), R.lampM)
  lamp.position.set(-0.15, 0.9, 0); ns.add(lamp)
  ns.position.set(-1.6, 0.25, 0.2); scene.add(ns)

  // 置物架 + 书
  const shelf = new THREE.Group()
  R.wood.push(box(0.08, 1.9, 0.9, '#d8b98a', 0, 0.95, 0, shelf).material)
  ;[0.4, 1.0, 1.6].forEach(h => R.wood.push(box(0.5, 0.06, 0.85, '#e8cfa5', 0.28, h, 0, shelf).material))
  const bookColors = ['#e07a5f', '#81b29a', '#c9a0dc', '#f2cc8f']
  for (let i = 0; i < 4; i++) {
    box(0.06, 0.26, 0.18, bookColors[i], 0.18 + i * 0.07, 0.56, 0.2, shelf)
  }
  box(0.26, 0.24, 0.24, '#9ecae8', 0.28, 1.16, 0.1, shelf)
  shelf.position.set(2.2, 0.25, -0.5); scene.add(shelf)

  // 地面收纳箱
  const fz = new THREE.Group()
  box(0.9, 0.55, 0.7, '#a5c8e4', -0.6, 0.28, 0, fz)
  box(0.6, 0.3, 0.6, '#f2b8a0', 0.4, 0.15, 0.2, fz)
  fz.position.set(0.2, 0.25, 1.6); scene.add(fz)

  // 热区
  ZONES.forEach(z => {
    const hg = new THREE.BoxGeometry(...z.box)
    const hm = new THREE.MeshBasicMaterial({ transparent: true, opacity: 0, depthWrite: false })
    const hit = new THREE.Mesh(hg, hm)
    hit.position.set(...z.center); hit.userData.zone = z.key
    scene.add(hit); hitTargets.push(hit); disposables.push(hg, hm)

    const g = new THREE.RingGeometry(0.2, 0.3, 28)
    const mat = new THREE.MeshBasicMaterial({ color: '#3f9e7a', transparent: true, opacity: 0.9, side: THREE.DoubleSide })
    const ring = new THREE.Mesh(g, mat)
    ring.rotation.x = -Math.PI / 2; ring.position.set(...z.pos); ring.userData.zone = z.key
    scene.add(ring); hitTargets.push(ring); zoneMarkers.push(ring)
    disposables.push(g, mat)
  })

  controls = new OrbitControls(camera, renderer.domElement)
  controls.enableDamping = true
  controls.minDistance = 4; controls.maxDistance = 14
  controls.maxPolarAngle = Math.PI / 2.1
  controls.target.set(0, 1, 0)
  controls.autoRotate = true
  controls.autoRotateSpeed = 0.8
  renderer.domElement.addEventListener('pointerdown', () => { controls.autoRotate = false }, { once: true })

  raycaster = new THREE.Raycaster()
  pointer = new THREE.Vector2()
  renderer.domElement.addEventListener('pointerdown', onDown)
  renderer.domElement.addEventListener('pointermove', onHover)
}

/* ================= 家园等级家具 ================= */
function buildLux() {
  const mk = (arr) => { const g = new THREE.Group(); arr.forEach(f => f(g)); scene.add(g); return g }

  luxGroups.lv1 = mk([(g) => {
    // 落地灯
    box(0.05, 1.2, 0.05, '#8b8b8b', -2.9, 0.85, -1.4, g)
    const shade = new THREE.Mesh(new THREE.CylinderGeometry(0.24, 0.3, 0.26, 14), EM('#ffe9a8', 0.85))
    shade.position.set(-2.9, 1.5, -1.4); g.add(shade)
  }, (g) => {
    // 小边桌
    box(0.5, 0.06, 0.5, '#d8b98a', -2.3, 0.5, 1.0, g)
    box(0.06, 0.5, 0.06, '#c9a06a', -2.5, 0.25, 0.8, g)
    box(0.06, 0.5, 0.06, '#c9a06a', -2.1, 0.25, 1.2, g)
  }])

  luxGroups.lv2 = mk([(g) => {
    // 小沙发
    box(0.9, 0.3, 0.55, '#9ecae8', 2.4, 0.42, 1.9, g)
    box(0.9, 0.45, 0.16, '#8fbfe0', 2.4, 0.72, 2.14, g)
    box(0.16, 0.3, 0.55, '#8fbfe0', 2.0, 0.5, 1.9, g)
    box(0.16, 0.3, 0.55, '#8fbfe0', 2.8, 0.5, 1.9, g)
    box(0.26, 0.12, 0.26, '#f2b8a0', 2.2, 0.62, 1.85, g)
  }, (g) => {
    // 两幅新挂画
    ;[0.2, 0.95].forEach((x, i) => {
      box(0.5, 0.6, 0.04, '#c9a06a', x, 2.0, -2.85, g, false)
      box(0.4, 0.48, 0.03, ['#cfe0f5', '#f5e6b8'][i], x, 2.0, -2.82, g, false)
    })
  }])

  luxGroups.lv3 = mk([(g) => {
    // 布艺吊灯
    const sh = new THREE.Mesh(new THREE.ConeGeometry(0.36, 0.3, 16), M('#fdf1e0'))
    sh.position.set(-1.6, 2.85, 0.9); sh.rotation.x = Math.PI; g.add(sh)
    box(0.02, 0.5, 0.02, '#cccccc', -1.6, 3.15, 0.9, g)
  }, (g) => {
    // 抱枕两个
    box(0.28, 0.14, 0.28, '#f7d6c4', -1.5, 0.78, -2.0, g)
    box(0.26, 0.13, 0.26, '#cfe0f5', -1.9, 0.78, -1.9, g)
  }])

  applyLevel(props.level)
}

function applyLevel(n) {
  if (!luxGroups.lv1) return
  luxGroups.lv1.visible = n >= 1
  luxGroups.lv2.visible = n >= 2
  luxGroups.lv3.visible = n >= 3
}

/* ================= 装饰 ================= */
function disposeGroup(g) {
  g.traverse(o => { if (o.isMesh) { o.geometry.dispose(); o.material.dispose() } })
}

function rebuildDecor(t) {
  if (decorGroup) { scene.remove(decorGroup); disposeGroup(decorGroup) }
  decorGroup = new THREE.Group()
  scene.add(decorGroup)
  const D = t.decor

  // 地毯
  if (t.rug.shape === 'circle') {
    const rug = new THREE.Mesh(new THREE.CylinderGeometry(1.05, 1.05, 0.05, 28), M(t.rug.color))
    rug.position.set(0.2, 0.28, 1.6); rug.receiveShadow = true
    decorGroup.add(rug)
  } else {
    const rug = new THREE.Mesh(new THREE.BoxGeometry(2.1, 0.05, 1.5), M(t.rug.color))
    rug.position.set(0.2, 0.28, 1.6); rug.receiveShadow = true
    decorGroup.add(rug)
    if (t.rug.color === '#b5654a') {
      for (let i = 0; i < 5; i++) {
        const line = new THREE.Mesh(new THREE.BoxGeometry(0.34, 0.02, 0.1), M('#e8c6a8'))
        line.position.set(-0.7 + i * 0.42, 0.31, 2.15)
        decorGroup.add(line)
      }
    }
  }

  if (D.curtain) {
    const cg = new THREE.BoxGeometry(0.34, 1.5, 0.08)
    const cm = M(t.paper)
    const c1 = new THREE.Mesh(cg, cm); c1.position.set(-1.62, 2.05, -2.8)
    const c2 = new THREE.Mesh(cg.clone(), cm.clone()); c2.position.set(0.42, 2.05, -2.8)
    decorGroup.add(c1, c2)
    const rod = new THREE.Mesh(new THREE.BoxGeometry(2.5, 0.04, 0.04), M('#c9a06a'))
    rod.position.set(-0.6, 2.8, -2.8); decorGroup.add(rod)
  }

  for (let i = 0; i < D.posters; i++) {
    const frame = new THREE.Mesh(new THREE.BoxGeometry(0.5, 0.66, 0.04), M(t.wood))
    frame.position.set(0.9 + i * 0.62, 2.15, -2.85)
    decorGroup.add(frame)
    const inner = new THREE.Mesh(new THREE.BoxGeometry(0.4, 0.55, 0.03), M(['#dff0e2', '#f7d6c4', '#cfe0f5', '#f5e6b8'][i % 4]))
    inner.position.set(0.9 + i * 0.62, 2.15, -2.82)
    decorGroup.add(inner)
  }

  const plantSpots = [[-3.02, 2.2], [-3.06, -0.4], [2.95, 1.9], [2.95, 0.9], [-2.6, 2.62]]
  for (let i = 0; i < Math.min(D.plants, plantSpots.length); i++) {
    const [px, pz] = plantSpots[i]
    const pot = new THREE.Mesh(new THREE.BoxGeometry(0.3, 0.34, 0.3), M(i % 2 ? '#e2907a' : '#c98a6b'))
    pot.position.set(px, 0.42, pz); pot.castShadow = true
    decorGroup.add(pot)
    const leafG = new THREE.ConeGeometry(0.16, 0.55, 6)
    for (const [lx, ly, lz, tilt] of [[-0.06, 0.28, 0, 0.22], [0.07, 0.35, 0.03, -0.18], [0, 0.24, -0.07, 0.5]]) {
      const leaf = new THREE.Mesh(leafG, M(i % 3 === 0 ? '#4f9a6f' : '#68b184'))
      leaf.position.set(px + lx, 0.42 + ly, pz + lz); leaf.rotation.z = tilt; leaf.castShadow = true
      decorGroup.add(leaf)
    }
  }

  if (D.fairy) {
    const colors = ['#ffe9a8', '#ffd1dc', '#c9e4ff', '#d9f7c5']
    for (let i = 0; i < 11; i++) {
      const bulb = new THREE.Mesh(new THREE.SphereGeometry(0.055, 8, 8), EM(colors[i % colors.length], 1.1))
      bulb.position.set(-3.0 + i * 0.55, 2.75 + Math.sin(i * 1.1) * 0.09, -2.78)
      decorGroup.add(bulb)
    }
  }

  if (D.neon) {
    const n1 = new THREE.Mesh(new THREE.BoxGeometry(6.6, 0.05, 0.05), EM('#8a7dff', 1.6)); n1.position.set(0, 0.36, -2.84)
    const n2 = new THREE.Mesh(new THREE.BoxGeometry(6.6, 0.05, 0.05), EM('#59e3d1', 1.4)); n2.position.set(0, 3.15, -2.84)
    const n3 = new THREE.Mesh(new THREE.BoxGeometry(0.05, 0.05, 5.6), EM('#ff7ad9', 1.3)); n3.position.set(-3.36, 2.9, 0)
    decorGroup.add(n1, n2, n3)
  }

  if (D.lantern) {
    const ball = new THREE.Mesh(new THREE.SphereGeometry(0.32, 16, 12), EM(t.paper, 0.75))
    ball.position.set(0.2, 2.55, 0.2); decorGroup.add(ball)
    const wire = new THREE.Mesh(new THREE.BoxGeometry(0.02, 0.45, 0.02), M('#cccccc'))
    wire.position.set(0.2, 3.0, 0.2); decorGroup.add(wire)
  }

  if (D.laptop) {
    box(0.52, 0.36, 0.04, '#6fa8dc', 1.35, 1.1, -2.2, decorGroup)
    box(0.52, 0.03, 0.3, '#8fbde8', 1.35, 0.92, -2.05, decorGroup)
  }
  if (D.books) {
    box(0.3, 0.06, 0.22, '#e07a5f', 2.0, 0.88, -1.95, decorGroup)
    box(0.28, 0.05, 0.2, '#81b29a', 2.0, 0.94, -1.95, decorGroup)
  }
  if (D.cup) {
    const cup = new THREE.Mesh(new THREE.CylinderGeometry(0.07, 0.06, 0.16, 10), M('#f2f2f2'))
    cup.position.set(1.0, 1.0, -2.1); decorGroup.add(cup)
  }
}

/* ================= 主题 ================= */
function applyTheme(i) {
  const t = THEMES[((i % THEMES.length) + THEMES.length) % THEMES.length]
  themeIndex.value = THEMES.indexOf(t)
  localStorage.setItem('dorm-theme', String(themeIndex.value))
  if (!scene) return
  scene.background.set(t.bg)
  scene.fog.color.set(t.fog)
  R.wallA.color.set(t.wall); R.wallB.color.set(t.wall)
  R.floor.color.set(t.floor); R.ground.color.set(t.ground)
  R.quilt.color.set(t.quilt); R.pillow.color.set(t.pillow)
  R.wood.forEach(m => m.color.set(t.wood))
  R.frame.forEach(m => m.color.set(t.paper))
  if (R.lampM) { R.lampM.color.set(t.paper); R.lampM.emissive.set(t.sun) }
  sunLight.color.set(t.sun); sunLight.intensity = t.sunPower
  rebuildDecor(t)
  return t
}

/* ================= 粒子 ================= */
function burst() {
  const colors = ['#8dd4b3', '#ffe9a8', '#ffd1dc', '#9ecae8', '#f4a88a']
  for (let i = 0; i < 34; i++) {
    const p = new THREE.Mesh(
      new THREE.SphereGeometry(0.05, 6, 6),
      new THREE.MeshBasicMaterial({ color: colors[i % colors.length], transparent: true })
    )
    p.position.set(0.2 + (Math.random() - 0.5) * 1.2, 1.6 + Math.random() * 0.6, 0.4 + (Math.random() - 0.5) * 1.2)
    const v = new THREE.Vector3((Math.random() - 0.5) * 2.2, 1.6 + Math.random() * 2.2, (Math.random() - 0.5) * 2.2)
    scene.add(p); particles.push({ mesh: p, v, life: 1.4 })
  }
}
function updateParticles(dt) {
  particles = particles.filter(p => {
    p.life -= dt
    if (p.life <= 0) { scene.remove(p.mesh); p.mesh.geometry.dispose(); p.mesh.material.dispose(); return false }
    p.v.y -= 3.2 * dt
    p.mesh.position.addScaledVector(p.v, dt)
    p.mesh.material.opacity = Math.min(1, p.life / 0.6)
    return true
  })
}

/* ================= 小人调度 ================= */
function placeAvatar(a, key) {
  const A = ANCHORS[key]
  a.target = { pos: new THREE.Vector3(...A.pos), rotY: A.rotY, rotZ: A.rotZ, action: A.action }
}

function updateAvatarPos(a, dt) {
  if (!a.target) return
  const { pos, rotY, rotZ, action } = a.target
  a.group.position.lerp(pos, Math.min(1, dt * 4.5))
  a.group.rotation.y += (rotY - a.group.rotation.y) * Math.min(1, dt * 4.5)
  a.group.rotation.z += (rotZ - a.group.rotation.z) * Math.min(1, dt * 4.5)
  a.setAction(action)
}

/** 随机切换小人在家里的活动 */
function scheduleActivity(t) {
  if (t < nextActivityAt) return
  if (t < playingUntil) { placeAvatar(me, 'playA'); return }
  const pool = ['idle', 'read', 'draw', 'pc', 'sleep', 'idle']
  const key = pool[Math.floor(Math.random() * pool.length)]
  placeAvatar(me, key)
  activityText.value = ANCHORS[key].text
  nextActivityAt = t + 7 + Math.random() * 6
}

/* ================= 对外 API ================= */
function inviteFriend(name = '好友') {
  if (!friend) {
    friend = createAvatar({ skin: '#ffe0c4', hair: '#6b4a2f', shirt: '#f7b2c0', pants: '#7f8fc9' })
    friend.group.scale.setScalar(0.95)
    scene.add(friend.group)
    friend.group.position.set(-3.2, 0.25, 2.6)   // 从门口走进来
  }
  friendLabel.value = name
  placeAvatar(friend, 'friend')
  activityText.value = `${name} 来到你的家园`
  return true
}

function playTogether() {
  if (!friend) inviteFriend(friendLabel.value || '好友')
  placeAvatar(me, 'playA')
  placeAvatar(friend, 'playB')
  playingUntil = clockT + 8
  activityText.value = '和好友一起蹦蹦跳跳'
  if (cat) { cat.setMode('run'); catTarget = 'play' }
  burst()
}

function spawnBaby() {
  if (baby) return true
  baby = createAvatar({ skin: '#ffe3cb', hair: '#5b3a26', shirt: '#fff0b3', pants: '#ffd1dc', scale: 0.55 })
  baby.group.position.set(-0.2, 0.28, 1.2)
  scene.add(baby.group)
  baby.setAction('sit')
  activityText.value = '家园迎来了小宝贝 👶'
  burst()
  return true
}

function removeFriend() {
  if (friend) { scene.remove(friend.group); friend = null }
  placeAvatar(me, 'idle')
}

/** 随机开盲盒 */
function randomTheme() {
  let i = Math.floor(Math.random() * THEMES.length)
  if (i === themeIndex.value) i = (i + 1) % THEMES.length
  const t = applyTheme(i)
  burst()
  controls.autoRotate = true
  controls.autoRotateSpeed = 2.4
  setTimeout(() => { controls.autoRotateSpeed = 0.8 }, 2600)
  return { name: t.name, desc: t.desc }
}

const friendLabel = ref('')
defineExpose({
  setTheme: applyTheme, randomTheme, themeIndex, themes: THEMES,
  inviteFriend, playTogether, spawnBaby, removeFriend, setLevel: applyLevel,
  friendLabel, activityText,
})

watch(() => props.level, (n) => applyLevel(n))

/* ================= 交互 ================= */
let downXY = null
function onDown(e) { downXY = [e.clientX, e.clientY] }
function toPointer(e) {
  const rect = renderer.domElement.getBoundingClientRect()
  pointer.x = ((e.clientX - rect.left) / rect.width) * 2 - 1
  pointer.y = -((e.clientY - rect.top) / rect.height) * 2 + 1
  raycaster.setFromCamera(pointer, camera)
}
function onHover(e) {
  toPointer(e)
  const hit = raycaster.intersectObjects(hitTargets, false)[0]
  renderer.domElement.style.cursor = hit ? 'pointer' : 'grab'
}
function onTap(e) {
  toPointer(e)
  const hit = raycaster.intersectObjects(hitTargets, false)[0]
  if (hit) {
    const key = hit.object.userData.zone
    activeZone.value = ZONES.find(z => z.key === key)
    emit('pick', key)
  }
}

/* ================= 主循环 ================= */
let last = 0
let catAngle = 0
let dogAngle = Math.PI
let catTarget = 'roam'
let petSleepTimer = 20

function animate(tms) {
  rafId = requestAnimationFrame(animate)
  const dt = Math.min((tms - last) / 1000, 0.05); last = tms
  clockT = tms / 1000

  const pulse = 1 + Math.sin(clockT * 3) * 0.12
  zoneMarkers.forEach(r => r.scale.set(pulse, pulse, pulse))

  // 小人
  if (me) { scheduleActivity(clockT); updateAvatarPos(me, dt); me.update(clockT) }
  if (friend) { updateAvatarPos(friend, dt); friend.update(clockT) }
  if (baby) {
    // 宝宝在地毯附近小范围走动
    const r = 0.45
    const bx = 0.2 + Math.cos(clockT * 0.7) * r
    const bz = 1.9 + Math.sin(clockT * 0.7) * r
    baby.group.position.lerp(new THREE.Vector3(bx, 0.3, bz), dt * 2)
    baby.group.rotation.y = -clockT * 0.7
    baby.setAction(Math.sin(clockT) > 0.6 ? 'sit' : 'idle')
    baby.update(clockT)
  }

  // 猫：绕着地毯转圈，偶尔睡觉
  if (cat) {
    if (cat.mode !== 'sleep') {
      catAngle += dt * (cat.mode === 'run' ? 2.6 : 0.55)
      const r = 1.35
      const cx = 0.2 + Math.cos(catAngle) * r
      const cz = 1.35 + Math.sin(catAngle) * r
      cat.group.position.set(cx, 0.25, cz)
      cat.group.rotation.y = -catAngle + Math.PI / 2
    }
    cat.update(dt, clockT)
  }
  // 狗：在草坪和房间之间巡逻
  if (dog) {
    if (dog.mode !== 'sleep') {
      dogAngle += dt * (dog.mode === 'run' ? 1.8 : 0.32)
      const r = 2.6
      const dx = Math.cos(dogAngle) * r
      const dz = 1.9 + Math.sin(dogAngle) * r * 0.7
      dog.group.position.set(dx, 0.25, dz)
      dog.group.rotation.y = -dogAngle
    }
    dog.update(dt, clockT)
  }
  // 宠物睡觉计时
  petSleepTimer -= dt
  if (petSleepTimer <= 0) {
    petSleepTimer = 18 + Math.random() * 12
    ;[cat, dog].forEach(p => {
      if (!p) return
      if (p.mode === 'sleep') p.setMode('roam')
      else if (Math.random() < 0.4) p.setMode('sleep')
    })
  }

  updateParticles(dt)
  controls.update()
  renderer.render(scene, camera)
}

onMounted(() => {
  renderer = new THREE.WebGLRenderer({ antialias: true })
  renderer.setPixelRatio(Math.min(window.devicePixelRatio, 2))
  renderer.setSize(container.value.clientWidth, container.value.clientHeight)
  renderer.shadowMap.enabled = true
  renderer.shadowMap.type = THREE.PCFSoftShadowMap
  renderer.outputColorSpace = THREE.SRGBColorSpace
  renderer.toneMapping = THREE.ACESFilmicToneMapping
  renderer.toneMappingExposure = 1.05
  container.value.appendChild(renderer.domElement)
  renderer.domElement.addEventListener('pointerup', (e) => {
    if (downXY && Math.hypot(e.clientX - downXY[0], e.clientY - downXY[1]) < 8) onTap(e)
    downXY = null
  })

  buildRoom()
  buildLux()
  applyTheme(Number(localStorage.getItem('dorm-theme') ?? 0))

  // 主角小人
  me = createAvatar({ skin: '#ffd8b5', hair: '#3b2b23', shirt: '#8fd0ae', pants: '#5a7ba6' })
  me.group.position.set(-0.55, 0.25, 0.75)
  scene.add(me.group)
  placeAvatar(me, 'idle')

  // 猫狗
  cat = createPet('cat')
  cat.group.position.set(1.4, 0.25, 1.6)
  scene.add(cat.group)
  dog = createPet('dog')
  dog.group.position.set(0, 0.25, 1.9)
  scene.add(dog.group)

  animate(0)
  window.addEventListener('resize', onResize)
})

function onResize() {
  if (!container.value) return
  camera.aspect = container.value.clientWidth / container.value.clientHeight
  camera.updateProjectionMatrix()
  renderer.setSize(container.value.clientWidth, container.value.clientHeight)
}

onBeforeUnmount(() => {
  cancelAnimationFrame(rafId)
  window.removeEventListener('resize', onResize)
  disposables.forEach(d => d.dispose())
  if (decorGroup) disposeGroup(decorGroup)
  renderer?.dispose()
})
</script>

<template>
  <div class="relative w-full h-full">
    <div ref="container" class="w-full h-full rounded-3xl overflow-hidden touch-none shadow-sm" />

    <!-- 风格切换 -->
    <div class="absolute top-3 right-3 flex flex-col gap-1 items-end max-h-[62%] overflow-y-auto">
      <span class="text-[10px] bg-white/85 backdrop-blur px-2.5 py-1 rounded-full text-gray-500 shrink-0">🎁 宿舍风格</span>
      <button v-for="(t, i) in themes" :key="i" @click="setTheme(i)"
        class="text-[11px] px-2.5 py-1 rounded-full backdrop-blur border transition shrink-0"
        :class="themeIndex === i ? 'bg-mint-500 text-white border-mint-500' : 'bg-white/85 border-white text-gray-500'">
        {{ t.name }}
      </button>
    </div>

    <!-- 状态气泡 -->
    <div class="absolute top-3 left-3 text-xs bg-white/85 backdrop-blur px-3 py-1.5 rounded-full text-gray-600">
      💬 小人正在：{{ activityText }}
    </div>

    <!-- 底部热区 -->
    <div class="absolute bottom-3 left-0 right-0 flex justify-center gap-2 flex-wrap px-2">
      <button v-for="z in ZONES" :key="z.key"
        class="px-3 py-1.5 rounded-full text-xs bg-white/90 backdrop-blur border shadow-sm transition"
        :class="activeZone?.key === z.key ? 'bg-mint-500 text-white border-mint-500' : 'border-mint-200 text-mint-700'"
        @click="activeZone = z; emit('pick', z.key)">
        {{ z.label }}
      </button>
    </div>
  </div>
</template>
