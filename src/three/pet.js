import * as THREE from 'three'

/**
 * 低模小宠物：猫 / 狗
 * createPet('cat'|'dog') → { group, update(dt, t, mode), setMode }
 * mode: 'roam' 走动 / 'sleep' 趴着睡 / 'run' 跑向主人
 */
const M = (c) => new THREE.MeshLambertMaterial({ color: c })

export function createPet(type = 'cat') {
  const isCat = type === 'cat'
  const g = new THREE.Group()
  const fur = isCat ? '#f0b27a' : '#c9a06a'
  const dark = isCat ? '#d99a5b' : '#a9825a'

  // 身体
  const body = new THREE.Mesh(new THREE.BoxGeometry(isCat ? 0.42 : 0.56, 0.2, 0.24), M(fur))
  body.position.y = 0.2; body.castShadow = true
  g.add(body)

  // 头
  const head = new THREE.Mesh(new THREE.SphereGeometry(isCat ? 0.15 : 0.18, 14, 12), M(fur))
  head.position.set(isCat ? 0.26 : 0.36, 0.26, 0); head.castShadow = true
  g.add(head)

  // 耳朵
  const earG = new THREE.ConeGeometry(0.055, 0.12, 5)
  const earM = M(dark)
  for (const z of [-0.07, 0.07]) {
    const ear = new THREE.Mesh(earG, earM)
    ear.position.set(isCat ? 0.26 : 0.36, 0.39, z)
    g.add(ear)
  }

  // 眼睛（黑点）
  const eG = new THREE.SphereGeometry(0.022, 6, 6)
  const eM = new THREE.MeshBasicMaterial({ color: '#2b2b2b' })
  for (const z of [-0.06, 0.06]) {
    const e = new THREE.Mesh(eG, eM)
    e.position.set(isCat ? 0.39 : 0.51, 0.28, z)
    g.add(e)
  }

  // 尾巴
  const tail = new THREE.Mesh(new THREE.BoxGeometry(0.06, 0.06, 0.3), M(dark))
  tail.position.set(isCat ? -0.22 : -0.3, 0.28, 0)
  g.add(tail)

  // 四条腿
  const legs = []
  const legG = new THREE.BoxGeometry(0.06, 0.16, 0.06)
  const legM = M(dark)
  const positions = isCat
    ? [[0.12, 0.08], [0.12, -0.08], [-0.12, 0.08], [-0.12, -0.08]]
    : [[0.18, 0.09], [0.18, -0.09], [-0.18, 0.09], [-0.18, -0.09]]
  positions.forEach(([x, z]) => {
    const leg = new THREE.Mesh(legG, legM)
    leg.position.set(x, 0.08, z)
    leg.castShadow = true
    g.add(leg); legs.push(leg)
  })

  // 影子
  const sh = new THREE.Mesh(
    new THREE.CircleGeometry(isCat ? 0.22 : 0.28, 14),
    new THREE.MeshBasicMaterial({ color: '#000', transparent: true, opacity: 0.1 })
  )
  sh.rotation.x = -Math.PI / 2; sh.position.y = 0.005
  g.add(sh)

  let mode = 'roam'
  const setMode = (m) => { mode = m }

  function update(dt, t) {
    if (mode === 'sleep') {
      body.position.y = 0.14
      body.rotation.z = 0
      head.position.y = 0.16
      tail.rotation.y = Math.sin(t * 0.8) * 0.12
      legs.forEach(l => { l.scale.y = 0.5; l.position.y = 0.05 })
      g.rotation.z = 0
      return
    }
    // 走动：腿摆动 + 身体起伏
    const speed = mode === 'run' ? 14 : 7
    body.position.y = 0.2 + Math.abs(Math.sin(t * speed)) * 0.02
    head.position.y = 0.26 + Math.abs(Math.sin(t * speed)) * 0.02
    legs.forEach((l, i) => {
      l.scale.y = 1
      l.position.y = 0.08
      l.rotation.x = Math.sin(t * speed + (i % 2 ? Math.PI : 0)) * 0.5
    })
    tail.rotation.y = Math.sin(t * (mode === 'run' ? 12 : 5)) * 0.5
    g.rotation.z = 0
  }

  /** 让宠物躺下（睡姿） */
  function lieDown() {
    body.position.y = 0.14
  }

  return { group: g, update, setMode, lieDown, get mode() { return mode } }
}
