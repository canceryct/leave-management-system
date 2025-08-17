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
    <header v-if="userProfile" style="background-color: #f0f2f5; padding: 10px 20px; display: flex; justify-content: flex-end; align-items: center; border-bottom: 1px solid #e0e0e0;">
      <span>當前使用者: <strong>{{ userProfile.full_name || userProfile.email }}</strong></span>
      
      <div v-if="userProfile.role === 'admin'" style="margin-left: 1em;">
        <el-button v-if="$route.path.startsWith('/admin')" @click="$router.push('/dashboard')" size="small">
          返回月曆
        </el-button>
        <el-button v-else type="primary" @click="$router.push('/admin/users')" size="small">
          管理後台
        </el-button>
      </div>

      <el-button @click="handleLogout" size="small" style="margin-left: 1em;">登出</el-button>
    </header>
    
    <main>
      <router-view />
    </main>
  </div>
</template>

<style>
body { margin: 0; font-family: -apple-system, BlinkMacSystemFont, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif; }
</style>