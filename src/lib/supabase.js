import { createClient } from '@supabase/supabase-js'

/**
 * Supabase 客户端
 * 密钥从环境变量读取：.env 文件中配置 VITE_SUPABASE_URL / VITE_SUPABASE_ANON_KEY
 * anon key 只是前端公开密钥，真正的权限由 Supabase RLS（行级安全）在数据库端控制。
 */
export const supabase = createClient(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_ANON_KEY
)
