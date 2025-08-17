<script setup>
import { ref } from 'vue';
import { supabase } from '../supabase';
import { useRouter } from 'vue-router';
import { ElMessage, ElNotification } from 'element-plus';

const router = useRouter();
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
    // --- 步驟一：建立「更新密碼」和「超時」的賽跑 ---
    const updateUserPromise = supabase.auth.updateUser({ password: newPassword.value });
    const timeoutPromise = new Promise((_, reject) => 
      setTimeout(() => reject(new Error('timeout')), 7000) // 設定 7 秒超時
    );

    // 等待比賽結果
    const { data: { user }, error: updateUserError } = await Promise.race([updateUserPromise, timeoutPromise]);
    
    // --- 步驟二：如果比賽是「正常成功」結束的 ---
    if (updateUserError) {
      // 如果 Supabase 快速地回傳了一個錯誤 (例如密碼相同)，我們在這裡處理它
      throw updateUserError;
    }
    
    // 只有在完全成功時，才繼續執行後續步驟
    await supabase.rpc('set_password_as_changed');
    await supabase.auth.signOut();
    ElNotification.success({
      title: '成功',
      message: '密碼已成功更新！請使用您的新密碼重新登入。',
    });
    router.push('/login');

  } catch (error) {
    // --- 步驟三：處理所有異常情況 ---
    if (error.message === 'timeout') {
      // 這是「卡住」時的處理流程
      ElNotification({
        title: '請求已發送',
        message: '您的密碼更新請求已在背景處理。5秒後將自動為您安全登出並返回登入頁面。',
        type: 'info',
        duration: 5000
      });
      
      setTimeout(() => {
        supabase.auth.signOut(); // 發送登出指令，但不等待
        window.location.href = '/login?action=signout'; // 強制重載到帶有指令的登入頁
      }, 5000);

    } else {
      // 這是其他真實的錯誤 (例如密碼強度不足、新舊密碼相同等)
      if (error.message && error.message.toLowerCase().includes('same as the old')) {
        ElMessage.error('新密碼不能與舊密碼相同！');
      } else if (error.message && error.message.toLowerCase().includes('password should be stronger')) {
        ElMessage.error('密碼強度不足！請使用更複雜的密碼組合。');
      } else {
        ElMessage.error('密碼設定失敗: ' + error.message);
      }
      loading.value = false; // 只有在真實錯誤時才解鎖按鈕
    }
  } 
  // 注意：我們故意不在 finally 中設定 loading = false，以確保在 5 秒倒數期間，按鈕保持禁用狀態。
}
</script>

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