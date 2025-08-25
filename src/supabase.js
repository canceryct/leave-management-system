import { createClient } from '@supabase/supabase-js'

const supabaseUrl = import.meta.env.VITE_SUPABASE_URL
const supabaseAnonKey = import.meta.env.VITE_SUPABASE_ANON_KEY

// ✨ 1. 建立一個符合 Supabase 要求的 sessionStorage 適配器
const sessionStorageAdapter = {
  getItem: (key) => {
    return sessionStorage.getItem(key)
  },
  setItem: (key, value) => {
    sessionStorage.setItem(key, value)
  },
  removeItem: (key) => {
    sessionStorage.removeItem(key)
  },
}

// ✨ 2. 在建立 Supabase Client 時，告訴它使用我們新的適配器
export const supabase = createClient(supabaseUrl, supabaseAnonKey, {
  auth: {
    storage: sessionStorageAdapter, // 指定使用 sessionStorage
    autoRefreshToken: true,
    persistSession: true,
    detectSessionInUrl: true
  },
})