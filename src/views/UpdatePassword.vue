<script setup>
import { ref } from 'vue';
import { supabase } from '../supabase';
import { ElMessage, ElNotification } from 'element-plus';

const newPassword = ref('');
const confirmPassword = ref('');
const loading = ref(false);

async function handleChangePassword() {
  // --- 前端驗證 ---
  if (!newPassword.value || !confirmPassword.value) { ElMessage.error('請輸入並確認您的新密碼'); return; }
  if (newPassword.value.length < 6) { ElMessage.error('密碼長度至少需要 6 個字元'); return; }
  if (newPassword.value !== confirmPassword.value) { ElMessage.error('兩次輸入的密碼不一致！'); return; }

  loading.value = true;
  try {
    const updateUserPromise = supabase.auth.updateUser({ password: newPassword.value });
    const timeoutPromise = new Promise((_, reject) => 
      setTimeout(() => reject(new Error('timeout')), 7000)
    );
    await Promise.race([updateUserPromise, timeoutPromise]);
    
    // --- 理想的成功路徑 ---
    await supabase.rpc('set_password_as_changed');
    await supabase.auth.signOut();
    ElNotification.success('密碼已成功更新！請使用您的新密碼重新登入。');
    router.push('/login');

  } catch (error) {
    if (error.message === 'timeout') {
      // --- 卡住時的處理流程 ---
      ElNotification({
        title: '請求已發送',
        message: '您的密碼更新請求已在背景處理。5秒後將自動為您安全登出並返回登入頁面。',
        type: 'info',
        duration: 5000
      });
      
      setTimeout(() => {
        // ✨ 只負責導航到帶有指令的 URL
        window.location.href = '/login?action=signout'; 
      }, 5000);

    } else {
      ElMessage.error('密碼更新失敗: ' + error.message);
      loading.value = false;
    }
  } 
}
</script>git push

<template>
  <div class="password-update-container">
    <div class="form-wrapper">
      <h2>設定您的新密碼</h2>
      <p>請為您的帳號設定一個新的、安全的密碼。</p>
      
      <form @submit.prevent="handleChangePassword">
        <div class="input-group">
          <label for="new-password">新密碼</label>
          <input 
            id="new-password"
            v-model="newPassword" 
            type="password" 
            placeholder="請輸入新密碼 (至少6個字元)" 
            required 
          />
        </div>
        <div class="input-group">
          <label for="confirm-password">確認新密碼</label>
          <input 
            id="confirm-password"
            v-model="confirmPassword" 
            type="password" 
            placeholder="請再次輸入新密碼" 
            required 
          />
        </div>
        <button type="submit" :disabled="loading">
          {{ loading ? '更新中...' : '確認並設定密碼' }}
        </button>
      </form>
    </div>
  </div>
</template>

<style scoped>
.change-password-container {
  display: flex;
  justify-content: center;
  align-items: center;
  min-height: 80vh;
  background-color: #f5f5f5;
}
.form-wrapper {
  padding: 2rem 3rem;
  background-color: white;
  border-radius: 8px;
  box-shadow: 0 4px 12px rgba(0, 0, 0, 0.1);
  width: 100%;
  max-width: 450px;
  text-align: center;
}
h2 {
  margin-bottom: 1rem;
}
p {
  color: #666;
  margin-bottom: 2rem;
  line-height: 1.6;
}
.input-group {
  text-align: left;
  margin-bottom: 1.5rem;
}
.input-group label {
  display: block;
  margin-bottom: 0.5rem;
  font-weight: 500;
}
input {
  width: 100%;
  padding: 10px;
  border: 1px solid #ccc;
  border-radius: 4px;
  box-sizing: border-box; /* Ensures padding doesn't affect width */
}
button {
  width: 100%;
  padding: 12px;
  background-color: #409EFF; /* Element Plus Primary Color */
  color: white;
  border: none;
  border-radius: 4px;
  cursor: pointer;
  font-size: 16px;
  transition: background-color 0.3s;
}
button:disabled {
  background-color: #a0cfff;
  cursor: not-allowed;
}
button:not(:disabled):hover {
  background-color: #79bbff;
}
</style>