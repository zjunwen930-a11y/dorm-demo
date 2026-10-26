import * as THREE from 'three'

/**
 * Q 版小人（程序化低模）
 * createAvatar({ skin, hair, shirt, pants, scale }) → { group, setAction, update }
 * 动作：idle 站立 / read 看书 / pc 玩电脑 / draw 画画 / sleep 睡觉 / dance 蹦跳 / sit
 */
const M = (c) => new THREE.MeshLambertMaterial({ color: c })

export function createAvatar(opts = {}) {
  const {
    skin = '#ffd8b5', hair = '#3b2b23', shirt = '#8fd0ae', pants = '#5a7ba6', scale = 1,
  } = opts

  const root = new THREE.Group()      // 位置由外部控制
  const body = new THREE.Group()      // 朝向 / 躺下等整体姿态
  root.add(body)

  /* ---------- 头（大头 Q 版比例） ---------- */
  const headG = new THREE.Group()
  headG.position.y = 1.0

  const head = new THREE.Mesh(new THREE.SphereGeometry(0.26, 18, 14), M(skin))
  head.castShadow = true
  headG.add(head)

  // 头发（半球帽）
  const hairMesh = new THREE.Mesh(
    new THREE.SphereGeometry(0.275, 18, 12, 0, Math.PI * 2, 0, Math.PI * 0.58),
    M(hair)
  )
  hairMesh.position.y = 0.035
  hairMesh.castShadow = true
  headG.add(hairMesh)

  // 眼睛 + 腮红
  const eyeG = new THREE.SphereGeometry(0.026, 8, 8)
  const eyeM = M('#2b2b2b')
  const eyes = []
  for (const x of [-0.085, 0.085]) {
    const e = new THREE.Mesh(eyeG, eyeM)
    e.position.set(x, 0.0, 0.238)
    headG.add(e); eyes.push(e)
  }
  const blushG = new THREE.SphereGeometry(0.045, 8, 8)
  const blushM = new THREE.MeshBasicMaterial({ color: '#ffb3c1', transparent: true, opacity: 0.55 })
  for (const x of [-0.15, 0.15]) {
    const b = new THREE.Mesh(blushG, blushM)
    b.scale.set(1, 0.6, 0.4)
    b.position.set(x, -0.06, 0.2)
    headG.add(b)
  }
  body.add(headG)

  /* ---------- 躯干 ---------- */
  const torso = new THREE.Mesh(new THREE.BoxGeometry(0.34, 0.36, 0.22), M(shirt))
  torso.position.y = 0.68
  torso.castShadow = true
  body.add(torso)

  /* ---------- 四肢（带关节 pivot，方便做动作） ---------- */
  function makeLimb(len, w, color, px, py) {
    const pivot = new THREE.Group()
    pivot.position.set(px, py, 0)
    const mesh = new THREE.Mesh(new THREE.BoxGeometry(w, len, w), M(color))
    mesh.position.y = -len / 2
    mesh.castShadow = true
    pivot.add(mesh)
    body.add(pivot)
    return pivot
  }
  const armL = makeLimb(0.34, 0.09, shirt, -0.22, 0.84)
  const armR = makeLimb(0.34, 0.09, shirt, 0.22, 0.84)
  const legL = makeLimb(0.36, 0.11, pants, -0.09, 0.48)
  const legR = makeLimb(0.36, 0.11, pants, 0.09, 0.48)

  /* ---------- 脚下柔和影子 ---------- */
  const shadowG = new THREE.CircleGeometry(0.24, 16)
  const shadowM = new THREE.MeshBasicMaterial({ color: '#000000', transparent: true, opacity: 0.12 })
  const shadow = new THREE.Mesh(shadowG, shadowM)
  shadow.rotation.x = -Math.PI / 2
  shadow.position.y = 0.01
  root.add(shadow)

  root.scale.setScalar(scale)
  let action = 'idle'

  /** 切换动作 */
  function setAction(a) { action = a }

  /** 每帧动画：呼吸 / 摆臂 / 眨眼（用缩放模拟） */
  function update(t) {
    const w = Math.sin(t * 2.2)
    switch (action) {
      case 'read':          // 坐着看书：双手前伸微动，低头
        headG.rotation.x = 0.28
        armL.rotation.x = -1.15; armR.rotation.x = -1.15
        armL.rotation.z = 0.12; armR.rotation.z = -0.12
        legL.rotation.x = -1.4; legR.rotation.x = -1.4
        break
      case 'pc':            // 玩电脑：双手前伸敲键盘
        headG.rotation.x = 0.12
        armL.rotation.x = -1.25 + Math.sin(t * 9) * 0.05
        armR.rotation.x = -1.25 - Math.sin(t * 9) * 0.05
        legL.rotation.x = -1.4; legR.rotation.x = -1.4
        break
      case 'draw':          // 地上画画：盘腿 + 手在地上划
        headG.rotation.x = 0.45
        armL.rotation.x = -0.9 + Math.sin(t * 3) * 0.12
        armR.rotation.x = -0.9 - Math.sin(t * 3) * 0.12
        legL.rotation.x = -1.55; legR.rotation.x = -1.55
        break
      case 'sleep':         // 睡觉：四肢放平
        headG.rotation.x = 0.15
        armL.rotation.x = 0.15; armR.rotation.x = 0.15
        legL.rotation.x = 0.05; legR.rotation.x = 0.05
        break
      case 'dance':         // 一起玩：抬手蹦跳
        headG.rotation.x = -0.1
        armL.rotation.x = -2.2 + w * 0.25
        armR.rotation.x = -2.2 - w * 0.25
        armL.rotation.z = 0.4 + w * 0.1
        armR.rotation.z = -0.4 - w * 0.1
        legL.rotation.x = w * 0.25; legR.rotation.x = -w * 0.25
        body.position.y = Math.abs(w) * 0.05
        break
      case 'sit':           // 坐椅子
        headG.rotation.x = 0.1
        armL.rotation.x = -0.7; armR.rotation.x = -0.7
        legL.rotation.x = -1.45; legR.rotation.x = -1.45
        break
      default:              // idle 站立：轻微呼吸摆动
        headG.rotation.x = 0
        armL.rotation.x = w * 0.06; armR.rotation.x = -w * 0.06
        armL.rotation.z = 0.05; armR.rotation.z = -0.05
        legL.rotation.x = 0; legR.rotation.x = 0
        body.position.y = 0
        body.rotation.z = 0
    }
    // 眨眼
    const blink = (t % 3.6) > 3.5 ? 0.15 : 1
    eyes.forEach(e => { e.scale.y = blink })
  }

  return { group: root, body, headG, setAction, update, get action() { return action } }
}
