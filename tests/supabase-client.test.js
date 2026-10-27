import test from 'node:test'
import assert from 'node:assert/strict'
import { initializeSupabase } from '../src/lib/supabase-client.js'

test('missing build variables keep startup safe without creating a network client', async () => {
  const connection = initializeSupabase(undefined, undefined, () => { throw new Error('must not be called') })
  assert.equal(connection.configured, false)
  assert.deepEqual(await connection.client.auth.getSession(), { data: { session: null }, error: null })
  const result = await connection.client.from('products').select('*').eq('zone', 'desk').order('created_at').limit(4)
  assert.equal(result.data, null)
  assert.equal(result.error.code, 'CONFIG_MISSING')
})
test('unconfigured authentication and mutations always fail, never pretend to succeed', async () => {
  const { client } = initializeSupabase('', '', () => {})
  for (const operation of [client.auth.signInWithPassword({}), client.from('orders').insert({}), client.from('favorites').delete().eq('id', 'x'), client.rpc('hot_products'), client.storage.from('images').upload('x', {})]) {
    assert.equal((await operation).error.code, 'CONFIG_MISSING')
  }
})
test('configured deployments retain the original real client and credentials', () => {
  const sentinel = {}
  const connection = initializeSupabase('https://example.supabase.co', 'test-publishable-key', (url, key) => {
    assert.equal(url, 'https://example.supabase.co'); assert.equal(key, 'test-publishable-key'); return sentinel
  })
  assert.equal(connection.client, sentinel)
  assert.equal(connection.configured, true)
})
test('invalid URL or a failing client initializer cannot blank the page', () => {
  assert.equal(initializeSupabase('invalid', 'key', () => {}).configured, false)
  assert.equal(initializeSupabase('https://example.supabase.co', 'key', () => { throw new Error('bad config') }).configured, false)
})
