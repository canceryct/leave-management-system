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