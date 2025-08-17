<script setup>
import { ref, onMounted } from 'vue';
import { supabase } from '../supabase';
import { useRouter } from 'vue-router';
import { ElMessage, ElNotification } from 'element-plus';

const router = useRouter();
const newPassword = ref('');
const confirmPassword = ref('');
const loading = ref(false);
const userEmail = ref('');

onMounted(async () => {
  const { data: { user } } = await supabase.auth.getUser();
  if (user) {
    userEmail.value = user.email;
  }
});

async function handleChangePassword() {
  // --- 前端驗證 ---
  if (!newPassword.value || !confirmPassword.value) {
    ElMessage.error('請輸入並確認您的新密碼');
    return;
  }
  if (newPassword.value.length < 6) {
    ElMessage.error('密碼長度至少需要 6 個字元');
    return;
  }
  if (newPassword.value !== confirmPassword.value) {
    ElMessage.error('兩次輸入的密碼不一致！');
    return;
  }

  loading.value = true;
  try {
    // 步驟一：更新密碼
    const { data: { user }, error: updateUserError } = await supabase.auth.updateUser({
      password: newPassword.value
    });
    if (updateUserError) throw updateUserError;

    // 步驟二：更新 profile 旗標
    const { error: rpcError } = await supabase.rpc('set_password_as_changed');
    if (rpcError) throw rpcError;
    
    // ✨ 關鍵改變：不再嘗試直接進入系統，而是先強制登出，清除所有不穩定的狀態
    await supabase.auth.signOut();

    // 步驟三：提示使用者，並導向到登入頁
    ElNotification({
      title: '成功',
      message: '密碼已成功更新！請使用您的新密碼重新登入。',
      type: 'success',
      duration: 0 // 讓提示持續顯示，直到使用者手動關閉
    });
    // 導向到登入頁
    router.push('/login');

  } catch (error) {
    ElMessage.error('密碼更新失敗: ' + error.message);
    console.error('Password change failed:', error);
  } finally {
    loading.value = false;
  }
}
</script>

<template>
  <div class="change-password-container">
    <div class="form-wrapper">
      <h2>設定新密碼</h2>
      <p v-if="userEmail">
        您正在為帳號 <strong>{{ userEmail }}</strong> 設定新密碼。<br />
        為了您的帳號安全，請立即變更管理員為您設定的初始密碼。
      </p>
      
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
          {{ loading ? '更新中...' : '設定新密碼' }}
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