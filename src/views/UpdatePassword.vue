<script setup>
import { ref } from 'vue';
import { supabase } from '../supabase';
import { useRouter } from 'vue-router';
import { ElMessage, ElNotification } from 'element-plus';

const router = useRouter();
const newPassword = ref('');
const confirmPassword = ref('');
const loading = ref(false);

// ✨✨✨ 這是重構後的、更穩固的函式 ✨✨✨
async function handleUpdatePassword() {
  // --- 1. 前端驗證 ---
  if (!newPassword.value || !confirmPassword.value) { ElMessage.error('請輸入並確認您的新密碼'); return; }
  if (newPassword.value.length < 6) { ElMessage.error('密碼長度至少需要 6 個字元'); return; }
  if (newPassword.value !== confirmPassword.value) { ElMessage.error('兩次輸入的密碼不一致！'); return; }

  loading.value = true;
  try {
    // --- 2. 執行密碼更新 ---
    const { data, error: updateUserError } = await supabase.auth.updateUser({
      password: newPassword.value
    });

    // --- 3. 錯誤優先處理 ---
    // 如果 updateUser 操作回傳了任何錯誤
    if (updateUserError) {
      // 根據不同的錯誤，給出不同的提示
      if (updateUserError.message.toLowerCase().includes('same as the old')) {
        ElMessage.error('新密碼不能與舊密碼相同！');
      } else if (updateUserError.message.toLowerCase().includes('password should be stronger')) {
        ElMessage.error('密碼強度不足！請使用更複雜的密碼組合。');
      } else {
        ElMessage.error('密碼設定失敗: ' + updateUserError.message);
      }
      // 處理完錯誤後，立刻終止函式，不再往下執行
      return; 
    }
    
    // --- 4. 只有在完全沒有錯誤時，才執行成功路徑 ---
    if (data.user) {
        // 更新 profile 旗標
        const { error: rpcError } = await supabase.rpc('set_password_as_changed');
        if (rpcError) throw rpcError; // 如果這裡出錯，會被下面的 catch 捕捉
    }
    
    // 登出並跳轉
    await supabase.auth.signOut();
    ElNotification.success('密碼已成功設定！將為您導向登入頁面。');
    router.push('/login');

  } catch (error) {
    // 這個 catch 現在只會捕捉 rpc 或 signOut 等預期外的錯誤
    console.error('Password update failed unexpectedly:', error);
    ElMessage.error('發生預期外的錯誤: ' + error.message);
  } finally {
    loading.value = false;
  }
}
</script>

<template>
  <div class="password-update-container">
    <div class="form-wrapper">
      <h2>設定您的新密碼</h2>
      <p>請為您的帳號設定一個新的、安全的密碼。</p>
      
      <form @submit.prevent="handleUpdatePassword">
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
          {{ loading ? '設定中...' : '確認並設定密碼' }}
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