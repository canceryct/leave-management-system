import { createApp } from 'vue';
import App from './App.vue';
import router from './router';
import { supabase } from './supabase';
import ElementPlus from 'element-plus';
import 'element-plus/dist/index.css';
import './style.css';

// 建立一個非同步的啟動函式，以便我們可以使用 await
async function initializeApp() {
  // ✨ 關鍵修改：在所有 Vue 相關操作之前，先檢查 URL 指令
  const urlParams = new URLSearchParams(window.location.search);
  if (urlParams.get('action') === 'signout') {
    // 如果發現指令，就先執行登出，並等待它完成
    await supabase.auth.signOut();
    // 登出後，將 URL 清理乾淨，避免重新整理時又觸發
    window.history.replaceState({}, document.title, "/login");
  }

  // --- 以下是您提供的、我們將保留的穩定版核心邏輯 ---
  const app = createApp(App);

  app.use(router);
  app.use(ElementPlus);

  let isAppMounted = false;

  supabase.auth.onAuthStateChange((event, session) => {
    if (!isAppMounted) {
      app.mount('#app');
      isAppMounted = true;
    }
  });
}

// 執行我們的啟動函式
initializeApp();