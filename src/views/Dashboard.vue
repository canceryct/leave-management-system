<script setup>
import { ref, reactive, onMounted, onUnmounted, watch } from 'vue';
import { supabase } from '../supabase';
import { ElMessage, ElNotification, ElMessageBox } from 'element-plus';
import FullCalendar from '@fullcalendar/vue3';
import dayGridPlugin from '@fullcalendar/daygrid';
import interactionPlugin from '@fullcalendar/interaction';
import listPlugin from '@fullcalendar/list';

const isMobile = ref(window.innerWidth < 768);
const handleResize = () => { isMobile.value = window.innerWidth < 768; };

const user = ref(null);
const userProfile = ref(null);
const isModalVisible = ref(false);
const selectedDate = ref('');
const leaveTypes = ref([]);
const potentialProxies = ref([]);
const calendarEvents = ref([]);
const isEditMode = ref(false);
const editingRecordId = ref(null);

const leaveForm = reactive({
  leave_type_id: null,
  proxy_user_id: null,
  leave_period: 'full',
});

const calendarOptions = ref({
  plugins: [dayGridPlugin, interactionPlugin, listPlugin],
  initialView: 'dayGridMonth',
  weekends: true, height: 'auto', events: [], dateClick: handleDateClick, eventClick: handleEventClick,
  locale: 'zh-tw', buttonText: { today: '今天' },
  headerToolbar: { right: 'prev,next today' },
  eventDidMount: function(info) {
    const proxyName = info.event.extendedProps.proxy_user_name;
    if (proxyName) { info.el.title = `代理人：${proxyName}`; }
  },
  eventContent: (arg) => {
    if (isMobile.value) {
      const parts = arg.event.title.split(' - ');
      const name = parts[0] || '';
      const periodTag = arg.event.extendedProps.leave_period === 'am' ? 'AM' : arg.event.extendedProps.leave_period === 'pm' ? 'PM' : '';
      return { html: `<div class="fc-event-main-frame"><div class="fc-event-title-container"><div class="fc-event-title fc-sticky">${name.slice(-2)}${periodTag}</div></div></div>` };
    }
    const title = arg.event.title;
    return { html: `<div class="fc-event-title fc-sticky">${title}</div>` };
  },
  // ✨ 關鍵修改 1：我們將 validRange 這一整段設定刪除，以解鎖歷史月份的導航
});

watch(isMobile, (isMobileValue) => {
  calendarOptions.value.initialView = isMobileValue ? 'listWeek' : 'dayGridMonth';
});

watch(calendarEvents, (newEvents) => {
  calendarOptions.value.events = newEvents;
});

// ✨ 關鍵修改 2：在函式開頭加入日期檢查
async function handleDateClick(arg) {
  const today = new Date();
  today.setHours(0, 0, 0, 0); // 將今天的時間設為 00:00:00，以確保日期比對的準確性
  if (arg.date < today) {
    ElMessage.info('無法在過去的日期登記假單');
    return; // 如果是過去的日期，就直接結束函式
  }

  const existingEvent = calendarEvents.value.find(event => event.start === arg.dateStr && event.extendedProps?.user_id === user.value.id);
  if (existingEvent) { ElMessage.warning('您在這天已經登記過假單了！'); return; }
  
  isEditMode.value = false;
  editingRecordId.value = null;
  Object.assign(leaveForm, { leave_type_id: null, proxy_user_id: null, leave_period: 'full' });
  selectedDate.value = arg.dateStr;
  await fetchPotentialProxies(arg.dateStr);
  isModalVisible.value = true;
}

async function handleEventClick(arg) {
  const event = arg.event;
  const props = event.extendedProps;
  const originalData = props.originalData;
  const titleParts = event.title.split(' - ');
  const leaveRequester = titleParts[0] || '(未知)';
  let leaveTypeName = '(未知)';
  if(titleParts[1]) {
    leaveTypeName = titleParts[1].split(' (')[0] || '';
  }
  const details = `<div><p><strong>請假人：</strong> ${leaveRequester}</p><p><strong>日期：</strong> ${event.startStr}</p><p><strong>假別：</strong> ${leaveTypeName}</p><p><strong>時段：</strong> ${props.leave_period === 'am' ? '上午' : props.leave_period === 'pm' ? '下午' : '全天'}</p><p><strong>代理人：</strong> ${props.proxy_user_name || '未指定'}</p></div>`;
  if (props.user_id === user.value.id) {
    ElMessageBox.confirm(`${details}<br><p>您想要對這筆假單做什麼操作？</p>`, '操作確認',
      { dangerouslyUseHTMLString: true, distinguishCancelAndClose: true, confirmButtonText: '刪除假單', cancelButtonText: '編輯假單', type: 'info' }
    ).then(() => { deleteLeaveRecord(event.id);
    }).catch(async (action) => {
      if (action === 'cancel') {
        isEditMode.value = true; editingRecordId.value = parseInt(event.id);
        await fetchPotentialProxies(event.startStr);
        Object.assign(leaveForm, {
          leave_type_id: originalData.leave_type_id, proxy_user_id: originalData.proxy_user_id, leave_period: originalData.leave_period,
        });
        selectedDate.value = event.startStr; isModalVisible.value = true;
      } else { ElMessage.info('已取消操作'); }
    });
  } else {
    ElMessageBox.alert(details, '假單詳情', { dangerouslyUseHTMLString: true, confirmButtonText: '關閉' });
  }
}

async function handleSubmitLeave() {
  if (!leaveForm.leave_type_id || !leaveForm.proxy_user_id) { ElMessage.error('請選擇或輸入代理人！'); return; }
  try {
    let response;
    if (isEditMode.value) {
      response = await supabase.rpc('update_leave_record', { p_record_id: editingRecordId.value, p_leave_type_id: leaveForm.leave_type_id, p_proxy_user_id: leaveForm.proxy_user_id, p_leave_period: leaveForm.leave_period });
    } else {
      const { data: proxyRecords } = await supabase.from('leave_records').select('id').eq('proxy_user_id', user.value.id).eq('leave_date', selectedDate.value);
      if (proxyRecords && proxyRecords.length > 0) {
        await ElMessageBox.confirm('提醒：您當天已是其他人的代理人，確定要繼續請假嗎？', '代理人提醒', { type: 'warning' });
      }
      response = await supabase.rpc('request_leave', { p_leave_date: selectedDate.value, p_leave_type_id: leaveForm.leave_type_id, p_proxy_user_id: leaveForm.proxy_user_id, p_leave_period: leaveForm.leave_period });
    }
    const { data, error } = response;
    if (error) throw error;
    if (data.success) {
      ElNotification.success(data.message);
      isModalVisible.value = false; await fetchLeaveRecords();
    } else { ElMessage.error(data.message); }
  } catch (error) {
    if (error.message !== 'Operation cancelled' && error !== 'cancel') { ElMessage.error(`操作失敗：${error.message}`); }
  }
}

async function fetchLeaveTypes() { const { data } = await supabase.from('leave_types').select('*'); leaveTypes.value = data; }

async function fetchPotentialProxies(date) {
  if (!userProfile.value?.group_id) { potentialProxies.value = []; return; }
  const { data: usersOnLeave } = await supabase.from('leave_records').select('user_id').eq('leave_date', date);
  const userIdsOnLeave = usersOnLeave?.map(r => r.user_id) || [];
  const { data: colleagues } = await supabase.from('profiles').select('id, full_name').eq('group_id', userProfile.value.group_id).neq('id', user.value.id);
  potentialProxies.value = colleagues?.filter(c => !userIdsOnLeave.includes(c.id)) || [];
}

async function fetchLeaveRecords() {
  if (!user.value) return;
  const { data, error } = await supabase.rpc('get_calendar_events');
  if (error) { console.error('Error fetching events:', error); return; }

  // 步驟一：排序所有假單紀錄
  const sortedRecords = data.sort((a, b) => {
    if (a.user_id < b.user_id) return -1;
    if (a.user_id > b.user_id) return 1;
    if (a.leave_type_id < b.leave_type_id) return -1;
    if (a.leave_type_id > b.leave_type_id) return 1;
    if (a.proxy_user_id < b.proxy_user_id) return -1;
    if (a.proxy_user_id > b.proxy_user_id) return 1;
    if (a.leave_date < b.leave_date) return -1;
    if (a.leave_date > b.leave_date) return 1;
    return 0;
  });

  // 步驟二：遍歷並合併連續的假單
  const mergedRecords = sortedRecords.reduce((acc, currentRecord) => {
    const lastRecord = acc.length > 0 ? acc[acc.length - 1] : null;
    
    // 計算期望的連續日期 (前一天的日期 + 1)
    const expectedDate = new Date(lastRecord?.endDate || 0);
    expectedDate.setDate(expectedDate.getDate() + 1);
    const expectedDateString = expectedDate.toISOString().split('T')[0];

    // 檢查是否可以合併
    const canMerge = lastRecord &&
                     lastRecord.user_id === currentRecord.user_id &&
                     lastRecord.leave_type_id === currentRecord.leave_type_id &&
                     lastRecord.proxy_user_id === currentRecord.proxy_user_id &&
                     currentRecord.leave_date === expectedDateString &&
                     currentRecord.leave_period === 'full' && // 只有全天假才能被連續合併
                     lastRecord.leave_period === 'full';

    if (canMerge) {
      // 如果可以合併，就只更新前一筆假單的結束日期
      lastRecord.endDate = currentRecord.leave_date;
    } else {
      // 如果不能合併，就新增一筆新的假單紀錄
      acc.push({
        ...currentRecord,
        startDate: currentRecord.leave_date,
        endDate: currentRecord.leave_date,
      });
    }
    return acc;
  }, []);

  // 步驟三：將合併後的資料，轉換成 FullCalendar 需要的格式
  calendarEvents.value = mergedRecords.map(record => {
    const fullName = record.full_name;
    let displayName = fullName || '(未知)';
    if (fullName && fullName.length > 2) {
      displayName = fullName.slice(-2);
    }
    const leaveTypeName = record.leave_type_name || '(未知)';
    
    // 只有半天假才需要顯示 AM/PM 標記
    const periodTag = record.leave_period === 'am' ? ' (AM)' : record.leave_period === 'pm' ? ' (PM)' : '';
    
    return {
      id: record.id,
      title: `${displayName} - ${leaveTypeName}${periodTag}`,
      start: record.startDate,
      // ✨ FullCalendar 會自動處理結束日期，我們需要加一天讓它包含最後一天
      end: new Date(new Date(record.endDate).getTime() + 24 * 60 * 60 * 1000).toISOString().split('T')[0],
      allDay: true,
      backgroundColor: record.user_id === user.value.id ? '#3788d8' : '#9aab6f',
      borderColor: record.user_id === user.value.id ? '#3788d8' : '#9aab6f',
      extendedProps: {
        user_id: record.user_id,
        proxy_user_name: record.proxy_user_name,
        leave_period: record.leave_period,
        originalData: {
          leave_type_id: record.leave_type_id,
          proxy_user_id: record.proxy_user_id,
          leave_period: record.leave_period,
        }
      }
    };
  });
}

async function deleteLeaveRecord(recordId) {
  const { error } = await supabase.from('leave_records').delete().eq('id', recordId);
  if (error) { ElMessage.error('刪除失敗：' + error.message); } 
  else { ElMessage.success('刪除成功！'); await fetchLeaveRecords(); }
}

async function initializePage() {
  try {
    const { data: { user: currentUser } } = await supabase.auth.getUser();
    if (!currentUser) return;
    user.value = currentUser;
    const { data: profileData, error: profileError } = await supabase.from('profiles').select('*').eq('id', user.value.id).single();
    if (profileError) throw profileError;
    userProfile.value = profileData;
    if (userProfile.value) {
      await Promise.all([ fetchLeaveRecords(), fetchLeaveTypes(), fetchPotentialProxies(new Date().toISOString().split('T')[0]) ]);
    } else {
      ElMessage.error('錯誤：找不到您的個人設定檔(Profile)，部分功能可能無法使用。');
    }
  } catch (error) {
    console.error("在初始化 Dashboard 時發生錯誤:", error);
    ElMessage.error(`頁面初始化失敗: ${error.message}`);
  }
}

const handleVisibilityChange = () => { if (!document.hidden) { location.reload(); } };

onMounted(() => {
  handleResize();
  initializePage();
  window.addEventListener('resize', handleResize);
  document.addEventListener('visibilitychange', handleVisibilityChange);
});

onUnmounted(() => {
  window.removeEventListener('resize', handleResize);
  document.removeEventListener('visibilitychange', handleVisibilityChange);
});
</script>

<template>
  <div class="page-container">
    <FullCalendar :options="calendarOptions" />
    <el-dialog v-model="isModalVisible" :title="isEditMode ? '編輯 ' + selectedDate + ' 的假單' : '登記 ' + selectedDate + ' 的假單'">
      <el-form :model="leaveForm" label-width="80px">
        <el-form-item label="請假時段">
          <el-radio-group v-model="leaveForm.leave_period">
            <el-radio-button label="full">全天</el-radio-button>
            <el-radio-button label="am">上午</el-radio-button>
            <el-radio-button label="pm">下午</el-radio-button>
          </el-radio-group>
        </el-form-item>
        <el-form-item label="假別">
          <el-select v-model="leaveForm.leave_type_id" placeholder="請選擇假別" style="width: 100%;">
            <el-option v-for="item in leaveTypes" :key="item.id" :label="item.name" :value="item.id" />
          </el-select>
        </el-form-item>
        <el-form-item label="代理人">
          <el-select v-model="leaveForm.proxy_user_id" placeholder="請選擇或輸入代理人姓名" filterable allow-create default-first-option style="width: 100%;">
            <el-option v-for="item in potentialProxies" :key="item.id" :label="item.full_name" :value="item.id" />
          </el-select>
        </el-form-item>
      </el-form>
      <template #footer>
        <el-button @click="isModalVisible = false">取消</el-button>
        <el-button type="primary" @click="handleSubmitLeave">確定送出</el-button>
      </template>
    </el-dialog>
  </div>
</template>

<style scoped>
.page-container {
  max-width: 1200px;
  margin: 0 auto;
  padding: 2em;
}
/* 1. 將所有週六(sat)和週日(sun)的日期「數字」設為淺紅色 */
:deep(.fc-day-sat .fc-daygrid-day-number),
:deep(.fc-day-sun .fc-daygrid-day-number) {
  color: #f56c6c; /* Element Plus 的危險紅色，很適合用來標示假日 */
}

/* 2. 將所有「過去」的日期「背景」設為淡灰色 */
:deep(.fc-day-past) {
  background-color: #f5f7fa; /* 一個比 f5f5f5 稍淺的灰色，更柔和 */
}
/* 讓過去日期的數字顏色變淡，但依然可見 */
:deep(.fc-day-past .fc-daygrid-day-number) {
    color: #a8abb2;
}

/* 3. (疊加效果) 讓「過去的週末」數字也恢復成紅色，使其在灰色背景上更突出 */
:deep(.fc-day-past.fc-day-sat .fc-daygrid-day-number),
:deep(.fc-day-past.fc-day-sun .fc-daygrid-day-number) {
  color: #f89898; /* 一個稍淺的紅色，與灰色背景搭配更和諧 */
}

:deep(.fc-day-past) {
  background-color: #f5f5f5;
}

@media (max-width: 768px) {
  .page-container {
    padding: 1em;
  }
  /* 手機標題 */
  :deep(.fc .fc-toolbar-title) {
    font-size: 1.1em;
  }
  :deep(.fc-event-title) {
    font-size: 0.53rem;
  }
  :deep(.fc-list-event) {
    padding-top: 8px;
    padding-bottom: 8px;
  }
   /* 在手機上，讓所有按鈕變得更小、更緊湊 */
  :deep(.fc .fc-button) {
    padding: 0.4em 0.7em; /* 減少上下和左右的內邊距 */
    font-size: 0.8em;    /* 縮小按鈕上的文字 */
  }
  :deep(.fc-daygrid-day-number) {
  font-size: 0.7em; /* 您可以調整這個數值，例如 1.1em 或 13px */
  /* color: #555; */ /* 也可以改變顏色 */
  /* font-weight: bold; */ /* 或是加粗 */
  }
}

/* --- ✨ 按鈕容器的樣式 (維持不變) --- */
.button-container {
  margin-top: 1.5rem; 
  text-align: right; 
}

/* --- ✨ 全新：模仿 el-button small 樣式的 CSS --- */
.update-password-button {
  /* 基本佈局和對齊 */
  display: inline-flex;
  justify-content: center;
  align-items: center;
  
  /* 外觀尺寸 - 模仿 size="small" */
  line-height: 1;
  font-size: 12px;
  font-weight: 500;
  padding: 8px 15px;
  border-radius: 4px;

  /* 顏色 - 模仿預設按鈕 */
  color: #b0afaf;
  background-color: #ffffff;
  border: 1px solid #dcdfe6;

  /* 其他屬性 */
  cursor: pointer;
  text-decoration: none;
  white-space: nowrap;
  transition: .1s;
}

/* 模仿滑鼠懸浮時的效果 */
.update-password-button:hover {
  color: #409EFF;
  border-color: #c6e2ff;
  background-color: #ecf5ff;
}
</style>