<script setup>
import { ref, onMounted, onUnmounted } from 'vue';
import { supabase } from '../../supabase';
import { ElMessage } from 'element-plus';

const quotas = ref([]);
const loading = ref(true);

async function fetchQuotas() {
  loading.value = true;
  try {
    const { data, error } = await supabase.rpc('get_group_quotas_list');
    if (error) throw error;
    quotas.value = data;
  } catch (error) {
    ElMessage.error('讀取名額設定失敗: ' + error.message);
  } finally {
    loading.value = false;
  }
}

async function handleQuotaChange(groupId, newLimit) {
  const limit = newLimit === null ? 0 : Number(newLimit);
  if (isNaN(limit) || limit < 0) {
    ElMessage.error('請輸入大於等於 0 的數字');
    fetchQuotas();
    return;
  }

  try {
    const { error } = await supabase
      .from('group_leave_quotas')
      .upsert({ group_id: groupId, limit_count: limit });
    
    if (error) throw error;

    ElMessage.success('名額上限已更新！');
    await fetchQuotas();
  } catch (error) {
    ElMessage.error('更新失敗: ' + error.message);
  }
}

const handleVisibilityChange = () => {
  if (!document.hidden) {
    console.log("頁面恢復可見，執行強制重新整理...");
    location.reload();
  }
};

onMounted(async () => {
  await fetchQuotas();
  document.addEventListener('visibilitychange', handleVisibilityChange);
});

onUnmounted(() => {
  document.removeEventListener('visibilitychange', handleVisibilityChange);
});
</script>

<template>
  <div style="padding: 2em;">
    <div style="display: flex; justify-content: space-between; align-items: center;">
      <h1>名額設定</h1>
      </div>
    <p>在這裡，您可以設定每個組別每日的總請假人數上限。</p>
    <p>如果某個組別未設定（或設為 0），則代表該組請假人數無上限。</p>

    <el-table 
      :data="quotas" 
      v-loading="loading" 
      border 
      stripe 
      style="width: 100%; margin-top: 20px;"
    >
      <el-table-column prop="name" label="組別名稱" min-width="300" />

      <el-table-column label="人數上限" width="200" align="center">
        <template #default="scope">
          <el-input-number
            :model-value="scope.row.limit_count"
            @change="(currentValue) => handleQuotaChange(scope.row.id, currentValue)"
            :min="0"
            controls-position="right"
            placeholder="無上限"
            style="width: 120px;"
          />
        </template>
      </el-table-column>
    </el-table>
  </div>
</template>

<style scoped>
/* 預留區塊，方便未來添加專屬於此頁面的樣式 */
</style>