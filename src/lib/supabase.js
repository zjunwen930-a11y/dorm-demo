import { createClient } from '@supabase/supabase-js'
import { initializeSupabase } from './supabase-client'

const connection = initializeSupabase(
  import.meta.env.VITE_SUPABASE_URL,
  import.meta.env.VITE_SUPABASE_ANON_KEY,
  createClient,
)

export const supabase = connection.client
export const supabaseConfigured = connection.configured
