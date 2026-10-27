const CONFIG_MESSAGE = '站点尚未配置数据服务，暂时无法登录或保存数据。'

// A missing preview build setting must never crash the whole Vue application.
// Every unavailable operation fails closed; no fake account, data or successful write.
export function createUnavailableClient() {
  const error = { code: 'CONFIG_MISSING', message: CONFIG_MESSAGE }
  const result = () => Promise.resolve({ data: null, count: null, error })
  function query() {
    const chain = { then: (resolve, reject) => result().then(resolve, reject) }
    for (const method of ['select', 'eq', 'order', 'limit', 'or', 'insert', 'update', 'delete', 'maybeSingle', 'single', 'in']) chain[method] = () => chain
    return chain
  }
  return {
    from: query,
    rpc: result,
    auth: {
      getSession: () => Promise.resolve({ data: { session: null }, error: null }),
      onAuthStateChange: () => ({ data: { subscription: { unsubscribe() {} } } }),
      signInWithPassword: result,
      signOut: result,
    },
    storage: { from: () => ({ upload: result, getPublicUrl: () => ({ data: { publicUrl: '' } }) }) },
  }
}

export function initializeSupabase(url, key, createClient) {
  try {
    if (typeof url !== 'string' || !url.trim() || typeof key !== 'string' || !key.trim()) throw new Error('Missing configuration')
    const parsed = new URL(url)
    if (!['https:', 'http:'].includes(parsed.protocol)) throw new Error('Invalid URL')
    return { client: createClient(url, key), configured: true }
  } catch {
    return { client: createUnavailableClient(), configured: false }
  }
}
