<script setup>
import { ref } from 'vue';
import { supabase } from '../supabase';
import { useRouter } from 'vue-router';

const router = useRouter();
const email = ref('');
const password = ref('');
const errorMessage = ref(null);
const successMessage = ref(null);

async function handleRegister() {
  try {
    const { data, error } = await supabase.auth.signUp({
      email: email.value,
      password: password.value,
    });

    if (error) throw error;

    // 顯示成功訊息，並提示使用者檢查信箱
    successMessage.value = '註冊成功！請檢查您的 Email 並點擊確認信中的連結。';
    errorMessage.value = null;

  } catch (error) {
    errorMessage.value = error.message;
    successMessage.value = null;
    console.error('Error signing up:', error);
  }
}
</script>

<template>
  <div>
    <h2>註冊新帳號</h2>
    <form @submit.prevent="handleRegister">
      <input type="email" v-model="email" placeholder="Email" required />
      <input type="password" v-model="password" placeholder="Password" required />
      <button type="submit">註冊</button>
    </form>
    <div v-if="errorMessage" style="color: red;">{{ errorMessage }}</div>
    <div v-if="successMessage" style="color: green;">{{ successMessage }}</div>
    <p>已經有帳號了？ <router-link to="/login">點此登入</router-link></p>
  </div>
</template>