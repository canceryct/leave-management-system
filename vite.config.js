import { defineConfig } from 'vite'
import vue from '@vitejs/plugin-vue'
import path from 'path' // 1. 引入 node.js 內建的 path 模組

// https://vitejs.dev/config/
export default defineConfig({
  plugins: [vue()],
  // 2. 新增 resolve.alias 設定區塊
  resolve: {
    alias: {
      // 3. 在這裡明確地定義 '@' 指向專案根目錄下的 'src' 資料夾
      '@': path.resolve(__dirname, './src'),
    }
  }
})