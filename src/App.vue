<script setup>
import { ref, onMounted } from 'vue'
import { supabase } from './supabase'

const groups = ref([])
const loading = ref(true)

async function fetchGroups() {
  const { data } = await supabase.from('groups').select('*')
  groups.value = data
  loading.value = false
}

onMounted(() => {
  fetchGroups()
})
</script>

<template>
  <main>
    <h1>請假登記系統 - 部署測試</h1>
    <div v-if="loading">讀取中...</div>
    <div v-else>
      <h3>已成功從 Supabase 讀取到以下組別：</h3>
      <ul>
        <li v-for="group in groups" :key="group.id">{{ group.name }}</li>
      </ul>
      <p style="color: green;">✅ 連線成功！</p>
    </div>
  </main>
</template>