<script setup>
import { ref } from 'vue';
import { supabase } from './supabase';
import { useRouter } from 'vue-router';

const router = useRouter();
const userProfile = ref(null);

// 唯一的 onAuthStateChange 監聽器，負責更新使用者狀態
supabase.auth.onAuthStateChange(async (event, session) => {
  if (session) {
    const { data } = await supabase
      .from('profiles')
      .select('full_name, role')
      .eq('id', session.user.id)
      .single();
    userProfile.value = { ...session.user, ...data };
  } else {
    userProfile.value = null;
  }
});

async function handleLogout() {
  const { error } = await supabase.auth.signOut();
  if (!error) {
    // 登出後直接導向，不再強制重載，讓流程更順暢
    router.push('/login');
  }
}
</script>

<template>
  <div>
    <header v-if="userProfile" class="app-header">
      <span class="current-user-display">
        <span class="desktop-only">當前使用者: </span>
        <strong>{{ userProfile.full_name || userProfile.email }}</strong>
      </span>
      
      <div v-if="userProfile.role === 'admin'" class="admin-buttons">
        <el-button v-if="$route.path.startsWith('/admin')" @click="$router.push('/dashboard')" size="small">
          返回月曆
        </el-button>
        <el-button v-else type="primary" @click="$router.push('/admin/users')" size="small">
          管理後台
        </el-button>
      </div>

      <el-button @click="handleLogout" size="small" class="logout-button">登出</el-button>
    </header>
    
    <main>
      <router-view />
    </main>
    <div v-if="userProfile" class="floating-toolbar">
      <router-link to="/dispatch-form" class="fab-button" title="新增派遣表單">
        <span class="fab-icon">+</span>
        </router-link>
    </div>
  </div>
</template>

<style>
body { margin: 0; font-family: sans-serif; }

.app-header {
  background-color: #f0f2f5;
  padding: 10px 20px;
  display: flex;
  justify-content: flex-end;
  align-items: center;
  border-bottom: 1px solid #e0e0e0;
  gap: 1em; /* ✨ 使用 gap 來控制間距 */
}
.current-user-display { font-size: 14px; color: #606266; }
.current-user-display strong { font-weight: 600; color: #303133; }
.desktop-only { display: inline; } /* 預設顯示 */

/*懸浮派遣表單CSS 樣式*/
.floating-toolbar {
  position: fixed;
  bottom: 30px;    /* 距離視窗底部 30px */
  left: 30px;      /* ✨ 關鍵修改：從 right 改為 left，將按鈕移到左下角 */
  z-index: 1000;
}

.fab-button {
  display: flex;
  justify-content: center;
  align-items: center;
  background-color: #409EFF;
  color: white;
  /* ✨ 關鍵修改：將尺寸從 56px 縮小為 50px */
  width: 50px;
  height: 50px;
  border-radius: 50%;
  box-shadow: 0 2px 8px rgba(0, 0, 0, 0.2);
  text-decoration: none;
  transition: all 0.3s ease;
}

.fab-button:hover {
  transform: scale(1.1);
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.25);
}

.fab-icon {
  /* ✨ 關鍵修改：將圖示大小從 28px 縮小為 24px */
  font-size: 24px;
  line-height: 1;
}

/* 針對手機的小螢幕，讓按鈕更靠近邊緣 */
@media (max-width: 768px) {
  .floating-toolbar {
    bottom: 20px;
    left: 20px;
  }
}

/* --- ✨ 新增的響應式設計 ✨ --- */
@media (max-width: 768px) {
  .app-header {
    padding: 8px 12px; /* 減少邊距 */
  }
  .current-user-display {
    font-size: 1.1em; /* 使用者顯示大小 */
  }
  .desktop-only {
    display: none; /* 在手機上隱藏「當前使用者」這幾個字 */
  }
}
</style>