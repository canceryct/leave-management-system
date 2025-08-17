<script setup>
import { ref } from 'vue';
import { supabase } from '../supabase';
import { useRouter } from 'vue-router';
import { View, Hide, Message, Lock } from '@element-plus/icons-vue';

// ✨ 1. 在這裡引入您放在 assets 資料夾的圖片
// 請將檔名替換成您自己的圖片檔名
import topImage from '@/assets/image-top.png';
import bottomImage from '@/assets/image-bottom.png';

// --- JavaScript 邏輯部分與之前完全相同，無需更動 ---
const router = useRouter();
const email = ref('');
const password = ref('');
const errorMessage = ref(null);
const loading = ref(false);
const passwordFieldType = ref('password');

async function handleLogin() {
  try {
    loading.value = true;
    errorMessage.value = null;
    if (!email.value || !password.value) {
      throw new Error('Email 和密碼不能為空');
    }
    
    // ✨ 直接使用 Email 和密碼登入，不再需要 RPC
    const { error } = await supabase.auth.signInWithPassword({
      email: email.value,
      password: password.value,
    });

    if (error) {
      // Supabase 會自動處理 email不存在 或 密碼錯誤 的情況
      throw error;
    }
    
    localStorage.removeItem('lastActivity');
    router.push('/dashboard');

  } catch (error) {
    errorMessage.value = 'Email 或密碼錯誤'; // 對使用者顯示統一的錯誤訊息
    console.error('Login failed:', error.message);
  } finally {
    loading.value = false;
  }
}
</script>

<template>
  <div class="login-page">
    <div class="login-card">
      <div class="form-side">
        <div class="form-container">
          <div class="form-header">
            <h1 class="title">歡迎回來</h1>
            <p class="subtitle">登入您的請假登記系統</p>
          </div>
          
          <el-form @submit.prevent="handleLogin" label-position="top" size="large" class="login-form">
            <el-form-item label="Email (電子信箱)">
              <el-input 
                v-model="email" 
                placeholder="請輸入您的 Email"
                :prefix-icon="Message"
                autocomplete="email" 
                type="email"
                required  
              />
            </el-form-item>
            
            <el-form-item label="密碼">
              <el-input
                v-model="password"
                :type="passwordFieldType"
                placeholder="請輸入密碼"
                :prefix-icon="Lock"
                autocomplete="current-password"
                required
              >
                <template #append>
                  <el-button 
                    :icon="passwordFieldType === 'password' ? View : Hide" 
                    @click="passwordFieldType = passwordFieldType === 'password' ? 'text' : 'password'"
                  />
                </template>
              </el-input>
            </el-form-item>

            <el-form-item>
              <el-button 
                type="primary" 
                native-type="submit" 
                :loading="loading" 
                class="login-button"
              >
                {{ loading ? '登入中...' : '登入' }}
              </el-button>
            </el-form-item>
            
            <div v-if="errorMessage" class="error-message">{{ errorMessage }}</div>
          </el-form>
        </div>
      </div>

      <div class="illustration-side">
        <img :src="topImage" alt="Top Illustration" class="illustration-image top-image" />
        <img :src="bottomImage" alt="Bottom Illustration" class="illustration-image bottom-image" />
      </div>
    </div>
  </div>
</template>

<style scoped>
/* ... CSS 變數和通用樣式保持不變 ... */
:root {
  --primary-color: #409EFF;
  --background-color: #f0f2f5;
  --card-background-color: #ffffff;
  --text-color: #303133;
  --subtitle-color: #606266;
  --illustration-bg-color: #f5f7fa;
}
.login-page { display: flex; justify-content: center; align-items: center; min-height: 100vh; background-color: var(--background-color); font-family: 'Helvetica Neue', Helvetica, 'PingFang SC', 'Hiragino Sans GB', 'Microsoft YaHei', '微软雅黑', Arial, sans-serif; }
.login-card { display: flex; width: 90%; max-width: 960px; min-height: 600px; background-color: var(--card-background-color); border-radius: 12px; box-shadow: 0 10px 40px rgba(0, 0, 0, 0.1); overflow: hidden; }
.form-side { flex: 1.2; display: flex; flex-direction: column; justify-content: center; align-items: center; padding: 3rem 4rem; }
.form-container { width: 100%; }
.form-header { text-align: left; width: 100%; margin-bottom: 2.5rem; }
.title { font-size: 2.2rem; font-weight: 700; color: var(--text-color); margin-bottom: 0.75rem; }
.subtitle { font-size: 1rem; color: var(--subtitle-color); }
.login-form .el-form-item { margin-bottom: 1.75rem; }
.login-button { width: 100%; font-size: 1rem; padding: 1.25rem 0; }
.error-message { color: #F56C6C; text-align: center; margin-top: 1rem; font-size: 0.9rem; }

.illustration-side {
  flex: 1;
  display: flex;
  flex-direction: column; 
  justify-content: center;
  align-items: center;
  background-color: var(--illustration-bg-color);
  padding: 2rem;
  gap: 2rem; 
  overflow: hidden;
}

/* ✨ 3. 將 CSS 選擇器從 svg 改為 img */
.illustration-side img {
  width: 90%;
  max-width: 300px;
  height: auto;
  object-fit: contain; /* 確保圖片比例正確 */
  opacity: 0;
  transform: translateY(20px);
}

/* ✨ 4. 使用 :nth-child 來為圖片分別設定動畫 */
.illustration-side img:nth-child(1) {
  animation: fadeInUp 0.7s 0.2s ease-out forwards;
}
.illustration-side img:nth-child(2) {
  animation: fadeInUp 0.7s 0.4s ease-out forwards;
}

@keyframes fadeInUp {
  from {
    opacity: 0;
    transform: translateY(20px);
  }
  to {
    opacity: 1;
    transform: translateY(0);
  }
}

@media (max-width: 860px) {
  .login-card { flex-direction: column; min-height: auto; width: 90%; max-width: 450px; box-shadow: 0 5px 20px rgba(0, 0, 0, 0.1); }
  .illustration-side { display: none; }
  .form-side { padding: 2.5rem; }
}
</style>