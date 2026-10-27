import test from 'node:test'
import assert from 'node:assert/strict'
import { readFile } from 'node:fs/promises'
import { Box3, Vector3 } from 'three'
import { GLTFLoader } from 'three/examples/jsm/loaders/GLTFLoader.js'
const assetUrl = new URL('../public/models/kenney/chair-rounded.glb', import.meta.url)

test('furniture asset is small, self-contained glTF 2 with no decoder requirement', async () => {
  const bytes = await readFile(assetUrl)
  assert.equal(bytes.readUInt32LE(0), 0x46546c67)
  assert.equal(bytes.readUInt32LE(4), 2)
  assert.equal(bytes.readUInt32LE(8), bytes.length)
  assert.ok(bytes.length < 50000)
  const length = bytes.readUInt32LE(12)
  const json = JSON.parse(bytes.subarray(20, 20 + length).toString())
  assert.ok(!(json.extensionsRequired?.length))
  assert.ok(json.buffers.every(buffer => !buffer.uri))
  assert.ok(!(json.images?.length))
})

test('Three.js r160 parses the chair and it fits the existing floor and desk anchor', async () => {
  const bytes = await readFile(assetUrl)
  const gltf = await new GLTFLoader().parseAsync(bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength), '')
  const root = gltf.scene
  let meshes = 0
  root.traverse(object => { if (object.isMesh) meshes++ })
  assert.ok(meshes > 0)
  const size = new Box3().setFromObject(root).getSize(new Vector3())
  assert.ok(size.y > 0 && Number.isFinite(size.y))
  root.scale.setScalar(0.82 / size.y)
  const bounds = new Box3().setFromObject(root)
  const center = bounds.getCenter(new Vector3())
  root.position.set(1.32 - center.x, 0.25 - bounds.min.y, -1.1 - center.z)
  const fitted = new Box3().setFromObject(root)
  assert.ok(Math.abs(fitted.min.y - 0.25) < 1e-6)
  assert.ok(Math.abs(fitted.getSize(new Vector3()).y - 0.82) < 1e-6)
  assert.ok(fitted.getSize(new Vector3()).x < 0.9, 'chair stays within the desk hotspot')
})

test('redistributed asset retains its upstream CC0 license', async () => {
  const license = await readFile(new URL('../public/models/kenney/License.txt', import.meta.url), 'utf8')
  assert.match(license, /Creative Commons Zero, CC0/)
  assert.match(license, /Kenney/)
})
