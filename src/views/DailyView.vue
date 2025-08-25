<script setup>
import { ref, onMounted, onUnmounted, computed, watch } from 'vue';
import { supabase } from '../supabase';
import { ElMessage } from 'element-plus';
import { ArrowLeft, ArrowRight } from '@element-plus/icons-vue';
import { useRouter } from 'vue-router';

const router = useRouter();
const loading = ref(false);
const selectedDate = ref(new Date());
const leaveData = ref([]);
const allGroups = ref([]);

const groupedLeaveData = computed(() => {
  const groupsWithLeave = allGroups.value.map(group => {
    const records = leaveData.value.filter(record => record.group_id === group.id);
    return { ...group, records: records };
  });
  return groupsWithLeave.filter(group => group.records.length > 0);
});

const formattedDate = computed(() => {
  const date = selectedDate.value;
  const options = { year: 'numeric', month: '2-digit', day: '2-digit', weekday: 'long' };
  return new Intl.DateTimeFormat('zh-TW', options).format(date);
});

function formatDateToYYYYMMDD(date) {
  const year = date.getFullYear();
  const month = (date.getMonth() + 1).toString().padStart(2, '0');
  const day = date.getDate().toString().padStart(2, '0');
  return `${year}-${month}-${day}`;
}

async function fetchData(date) {
  loading.value = true;
  const dateString = formatDateToYYYYMMDD(date);
  try {
    const [leaveRes, groupsRes] = await Promise.all([
      supabase.rpc('get_daily_leave_details', { p_date: dateString }),
      supabase.from('groups').select('*').order('id')
    ]);
    if (leaveRes.error) throw leaveRes.error;
    if (groupsRes.error) throw groupsRes.error;
    leaveData.value = leaveRes.data;
    const order = [7, 1, 2, 6, 3, 4, 5];
    allGroups.value = groupsRes.data.sort((a, b) => order.indexOf(a.id) - order.indexOf(b.id));
  } catch (error) {
    ElMessage.error(`讀取資料失敗: ${error.message}`);
    leaveData.value = [];
  } finally {
    loading.value = false;
  }
}

const prevDay = () => { const d = new Date(selectedDate.value); d.setDate(d.getDate() - 1); selectedDate.value = d; };
const nextDay = () => { const d = new Date(selectedDate.value); d.setDate(d.getDate() + 1); selectedDate.value = d; };

// ✨ 關鍵修正：將返回路徑從 '/' 改為 '/dashboard'
const goBackToCalendar = () => { router.push('/dashboard'); };

watch(selectedDate, (newDate) => { fetchData(newDate); });

const handleVisibilityChange = () => { if (!document.hidden) { location.reload(); } };

onMounted(() => {
  fetchData(selectedDate.value);
  document.addEventListener('visibilitychange', handleVisibilityChange);
});

onUnmounted(() => {
  document.removeEventListener('visibilitychange', handleVisibilityChange);
});
</script>

<template>
  <div class="daily-view-container whiteboard-style">
    <div class="header">
      <el-button :icon="ArrowLeft" @click="prevDay" circle class="whiteboard-button" />
      <el-date-picker
        v-model="selectedDate" type="date" placeholder="選擇日期"
        :editable="false" style="width: 100%; margin: 10px;"
        class="whiteboard-input"
      />
      <el-button :icon="ArrowRight" @click="nextDay" circle class="whiteboard-button" />
    </div>
    <h2 class="date-title whiteboard-text">{{ formattedDate }}</h2>
    <el-button @click="goBackToCalendar" class="back-button whiteboard-button">返回月曆</el-button>

    <div class="main-table-container">
      <el-skeleton :rows="10" animated v-if="loading" />
      <div v-else>
        <div v-if="groupedLeaveData.length === 0" class="no-data-tip whiteboard-text">
          當日無請假紀錄
        </div>
        <div v-else>
          <el-table :data="groupedLeaveData" row-key="id" border style="width: 100%" class="whiteboard-table">
            <el-table-column prop="name" label="組別" width="85" header-class-name="whiteboard-header-cell" class-name="whiteboard-cell" />
            <el-table-column label="請假人員詳細資訊" header-class-name="whiteboard-header-cell" class-name="whiteboard-cell">
              <template #default="scope">
                <div v-if="scope.row.records.length > 0">
                  <div class="inner-grid header-row">
                    <div class="requester-col whiteboard-text">請假人</div>
                    <div class="proxy-col whiteboard-text">代理人</div>
                  </div>
                  <div v-for="record in scope.row.records" :key="record.full_name" class="inner-grid record-row">
                    <div class="requester-col whiteboard-text">
                      {{ record.full_name }} - {{ record.leave_type_name }}
                      <span v-if="record.leave_period !== 'full'" class="period-tag whiteboard-tag">
                        {{ record.leave_period.toUpperCase() }}
                      </span>
                    </div>
                    <div class="proxy-col whiteboard-text">{{ record.proxy_user_name || '未指定' }}</div>
                  </div>
                </div>
                <div v-else class="no-leave-in-group whiteboard-text">
                  該組無人請假
                </div>
              </template>
            </el-table-column>
          </el-table>
        </div>
      </div>
    </div>
  </div>
</template>

<style scoped>
.daily-view-container {
  padding: 2em;
  max-width: 2000px;
  margin: 0 auto;
}

/* 白板風格 */
.whiteboard-style {
  background-color: #fafcfe; /* 淡藍色，模擬白板 */
  border: 2px solid #ccddee; /* 淺灰色邊框 */
  border-radius: 10px;
  padding: 1em;
}

.whiteboard-text {
  color: #333; /* 深灰色文字 */
}

.whiteboard-button {
  background-color: #e0e8f0; /* 淺藍灰色按鈕 */
  color: #333;
  border: 1px solid #aab8c2;
}
.whiteboard-button:hover {
  background-color: #d0d8e0;
}

.whiteboard-table {
  border-collapse: collapse;
  box-shadow: 0 2px 4px rgba(0, 0, 0, 0.1);
}
.whiteboard-cell {
  border: 1px solid #ddd;
  padding: 10px;
}
.whiteboard-header-cell {
  background-color: #e0e8f0;
  color: #333;
  font-weight: bold;
  padding: 12px;
  border: 1px solid #ccddee;
}

.whiteboard-tag {
  background-color: #dff0d8; /* 淡綠色標籤 */
  color: #3c763d; /* 深綠色文字 */
  border: 1px solid #d6e9c6;
}

.header {
  display: flex;
  justify-content: center;
  align-items: center;
  margin-bottom: 1rem;
}

.date-title {
  text-align: center;
  margin-bottom: 1.5rem;
  font-size: 2rem;
  font-weight: bold;
}

.back-button {
  margin-bottom: 1rem;
  display: block;
  margin-left: auto;
  margin-right: auto;
}

.main-table-container {
  border: 1px solid #ccddee;
  border-radius: 8px;
  overflow: hidden;
  min-height: 650px;
}

.no-data-tip {
  text-align: center;
  color: #777;
  font-size: 1.2rem;
  padding: 4rem 0;
}

.inner-grid {
  display: flex;
  align-items: center;
}

.record-row {
  padding: 10px 0;
  border-bottom: 1px solid #eee;
}
.record-row:last-child {
  border-bottom: none;
}

.header-row {
  color: #555;
  font-weight: bold;
  padding: 10px 0;
  background-color: #f8f8f8;
}

.requester-col {
  flex: 3;
  padding-left: 10px;
}

.proxy-col {
  flex: 2;
  padding-left: 10px;
  color: #777;
}

.no-leave-in-group {
  color: #999;
  padding: 10px;
  text-align: center;
}

/* 響應式設計 */
@media (max-width: 768px) {
  .daily-view-container {
    padding: 1em;
  }
  .date-title {
    font-size: 1.6rem;
  }
  .requester-col {
    flex: 2;
  }
  .proxy-col {
    flex: 1;
  }
  :deep(.el-table .cell) {
    padding: 8px;
    font-size: 0.9rem;
  }
}
</style>