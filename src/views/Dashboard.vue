<script setup>
import { ref, reactive, onMounted, onUnmounted, watch } from 'vue';
import { supabase } from '../supabase';
import { ElMessage, ElNotification, ElMessageBox } from 'element-plus';
import FullCalendar from '@fullcalendar/vue3';
import dayGridPlugin from '@fullcalendar/daygrid';
import interactionPlugin from '@fullcalendar/interaction';
import listPlugin from '@fullcalendar/list';
import { useRouter } from 'vue-router'; 

const router = useRouter();
const isMobile = ref(window.innerWidth < 768);
const handleResize = () => { isMobile.value = window.innerWidth < 768; };

const currentView = ref('calendar');

const user = ref(null);
const userProfile = ref(null);
const isModalVisible = ref(false);
const selectedDate = ref('');
const leaveTypes = ref([]);
const potentialProxies = ref([]);
const calendarEvents = ref([]);
const isEditMode = ref(false);
const editingRecordId = ref(null);

const rawLeaveRecords = ref([]);

const leaveForm = reactive({
  leave_type_id: null,
  proxy_user_id: null,
  leave_period: 'full',
});

const calendarOptions = ref({
  plugins: [dayGridPlugin, interactionPlugin, listPlugin],
  initialView: 'dayGridMonth',
  weekends: true, height: 'auto', events: [], 
  dateClick: handleDateClick, 
  eventClick: handleEventClick,
  locale: 'zh-tw', buttonText: { today: '今天' },
  headerToolbar: { right: 'prev,next today dailyView' },
  customButtons: {
    dailyView: {
      text: '以日檢視',
      click: () => {
        router.push('/daily-view'); 
      }
    }
  },
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
});

watch(isMobile, (isMobileValue) => {
  calendarOptions.value.initialView = isMobileValue ? 'listWeek' : 'dayGridMonth';
});

watch(calendarEvents, (newEvents) => {
  calendarOptions.value.events = newEvents;
});

async function handleDateClick(arg) {
  const today = new Date();
  today.setHours(0, 0, 0, 0);
  if (arg.date < today) {
    ElMessage.info('無法在過去的日期登記假單');
    return;
  }

  const myLeaveOnThisDay = rawLeaveRecords.value.find(
    record => record.leave_date === arg.dateStr && record.user_id === user.value.id
  );

  if (myLeaveOnThisDay) {
    triggerDayAction(myLeaveOnThisDay);
  } else {
    isEditMode.value = false;
    editingRecordId.value = null;
    Object.assign(leaveForm, { leave_type_id: null, proxy_user_id: null, leave_period: 'full' });
    selectedDate.value = arg.dateStr;
    await fetchPotentialProxies(arg.dateStr);
    isModalVisible.value = true;
  }
}

// 🔥 【核心修改】將提示文字的產生邏輯移入判斷式中
async function handleEventClick(arg) {
  const event = arg.event;
  const props = event.extendedProps;

  const startDate = event.startStr;
  const endDate = new Date(new Date(event.endStr).getTime() - 24 * 60 * 60 * 1000).toISOString().split('T')[0];
  const dateDisplay = startDate === endDate ? startDate : `${startDate} ~ ${endDate}`;

  const titleParts = event.title.split(' - ');
  const leaveRequester = titleParts[0] || '(未知)';
  let leaveTypeName = '(未知)';
  if(titleParts[1]) {
    leaveTypeName = titleParts[1].split(' (')[0] || '';
  }

  // 先建立不含提示的基本資訊
  let details = `<div><p><strong>請假人：</strong> ${leaveRequester}</p><p><strong>日期：</strong> ${dateDisplay}</p><p><strong>假別：</strong> ${leaveTypeName}</p><p><strong>時段：</strong> ${props.leave_period === 'am' ? '上午' : props.leave_period === 'pm' ? '下午' : '全天'}</p><p><strong>代理人：</strong> ${props.proxy_user_name || '未指定'}</p></div>`;

  if (props.user_id === user.value.id) {
    // 如果是自己的假單，才加上提示文字
    const hint = `<hr><p style="font-size: 0.85em; color: #888;">提示：若要編輯或針對個別日期刪除，請直接點擊該日期格子。</p>`;
    
    ElMessageBox.confirm(details + hint, '假單詳情', { // 將基本資訊和提示合併
      dangerouslyUseHTMLString: true,
      distinguishCancelAndClose: true,
      confirmButtonText: '刪除整筆假單',
      cancelButtonText: '關閉',
    }).then(() => {
      deleteLeavePeriod(props.componentIds);
    }).catch(() => {
      ElMessage.info('已取消操作');
    });
  } else {
    // 如果是別人的假單，直接顯示不含提示的基本資訊
    ElMessageBox.alert(details, '假單詳情', { dangerouslyUseHTMLString: true, confirmButtonText: '關閉' });
  }
}

async function triggerDayAction(record) {
  const details = `<div><p><strong>請假人：</strong> ${record.full_name || '(未知)'}</p><p><strong>日期：</strong> ${record.leave_date}</p><p><strong>假別：</strong> ${record.leave_type_name || '(未知)'}</p><p><strong>時段：</strong> ${record.leave_period === 'am' ? '上午' : record.leave_period === 'pm' ? '下午' : '全天'}</p><p><strong>代理人：</strong> ${record.proxy_user_name || '未指定'}</p></div>`;

  ElMessageBox.confirm(`${details}<br><p>您想要對這一天的假單做什麼操作？</p>`, '單日操作確認', {
    dangerouslyUseHTMLString: true,
    distinguishCancelAndClose: true,
    confirmButtonText: '刪除這一天',
    cancelButtonText: '編輯這一天',
  }).then(() => {
    deleteLeaveRecord(record.id);
  }).catch(async (action) => {
    if (action === 'cancel') {
      isEditMode.value = true;
      editingRecordId.value = record.id;
      selectedDate.value = record.leave_date;
      await fetchPotentialProxies(record.leave_date);
      Object.assign(leaveForm, {
        leave_type_id: record.leave_type_id,
        proxy_user_id: record.proxy_user_id,
        leave_period: record.leave_period,
      });
      isModalVisible.value = true;
    }
  });
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

  rawLeaveRecords.value = data;

  const sortedRecords = [...data].sort((a, b) => {
    if (a.user_id < b.user_id) return -1; if (a.user_id > b.user_id) return 1;
    if (a.leave_type_id < b.leave_type_id) return -1; if (a.leave_type_id > b.leave_type_id) return 1;
    if (a.proxy_user_id < b.proxy_user_id) return -1; if (a.proxy_user_id > b.proxy_user_id) return 1;
    if (a.leave_date < b.leave_date) return -1; if (a.leave_date > b.leave_date) return 1;
    return 0;
  });

  const mergedRecords = sortedRecords.reduce((acc, currentRecord) => {
    const lastRecord = acc.length > 0 ? acc[acc.length - 1] : null;
    const expectedDate = new Date(lastRecord?.endDate || 0);
    expectedDate.setDate(expectedDate.getDate() + 1);
    const expectedDateString = expectedDate.toISOString().split('T')[0];
    const canMerge = lastRecord &&
                     lastRecord.user_id === currentRecord.user_id &&
                     lastRecord.leave_type_id === currentRecord.leave_type_id &&
                     lastRecord.proxy_user_id === currentRecord.proxy_user_id &&
                     currentRecord.leave_date === expectedDateString &&
                     currentRecord.leave_period === 'full' &&
                     lastRecord.leave_period === 'full';
    if (canMerge) {
      lastRecord.endDate = currentRecord.leave_date;
      lastRecord.componentIds.push(currentRecord.id);
    } else {
      acc.push({
        ...currentRecord,
        startDate: currentRecord.leave_date,
        endDate: currentRecord.leave_date,
        componentIds: [currentRecord.id]
      });
    }
    return acc;
  }, []);

  calendarEvents.value = mergedRecords.map(record => {
    const fullName = record.full_name;
    let displayName = fullName || '(未知)';
    if (fullName && fullName.length > 2) { displayName = fullName.slice(-2); }
    const leaveTypeName = record.leave_type_name || '(未知)';
    const periodTag = record.leave_period === 'am' ? ' (AM)' : record.leave_period === 'pm' ? ' (PM)' : '';
    
    return {
      id: record.id.toString(),
      title: `${displayName} - ${leaveTypeName}${periodTag}`,
      start: record.startDate,
      end: new Date(new Date(record.endDate).getTime() + 24 * 60 * 60 * 1000).toISOString().split('T')[0],
      allDay: true,
      backgroundColor: record.user_id === user.value.id ? '#3788d8' : '#9aab6f',
      borderColor: record.user_id === user.value.id ? '#3788d8' : '#9aab6f',
      extendedProps: {
        user_id: record.user_id,
        proxy_user_name: record.proxy_user_name,
        leave_period: record.leave_period,
        componentIds: record.componentIds
      }
    };
  });
}

async function deleteLeaveRecord(recordId) {
  const { error } = await supabase.from('leave_records').delete().eq('id', recordId);
  if (error) { ElMessage.error('刪除失敗：' + error.message); } 
  else { ElMessage.success('刪除成功！'); await fetchLeaveRecords(); }
}

async function deleteLeavePeriod(recordIds) {
  ElMessageBox.confirm(`確定要刪除整筆假單嗎？`, '刪除整筆確認', {
    confirmButtonText: '確定刪除',
    cancelButtonText: '取消',
    type: 'warning',
  }).then(async () => {
    const { error } = await supabase.from('leave_records').delete().in('id', recordIds);
    if (error) {
      ElMessage.error('刪除整筆假單失敗：' + error.message);
    } else {
      ElMessage.success('已成功刪除整筆假單！');
      await fetchLeaveRecords();
    }
  }).catch(() => {
    ElMessage.info('已取消刪除操作');
  });
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

    <div class="button-container">
      <router-link to="/update-password" class="update-password-button">
        修改密碼
      </router-link>
    </div>

  </div>
</template>

<style scoped>
.page-container {
  max-width: 1200px;
  margin: 0 auto;
  padding: 2em;
}
:deep(.fc-day-sat .fc-daygrid-day-number),
:deep(.fc-day-sun .fc-daygrid-day-number) {
  color: #f56c6c;
}

:deep(.fc-day-past) {
  background-color: #f5f7fa;
}
:deep(.fc-day-past .fc-daygrid-day-number) {
    color: #a8abb2;
}

:deep(.fc-day-past.fc-day-sat .fc-daygrid-day-number),
:deep(.fc-day-past.fc-day-sun .fc-daygrid-day-number) {
  color: #f89898;
}

:deep(.fc-day-past) {
  background-color: #f5f5f5;
}

@media (max-width: 768px) {
  .page-container {
    padding: 1em;
  }
  :deep(.fc .fc-toolbar-title) {
    font-size: 1em;
  }
  :deep(.fc-event-title) {
    font-size: 0.6rem;
  }
  :deep(.fc-list-event) {
    padding-top: 8px;
    padding-bottom: 8px;
  }
  :deep(.fc .fc-button) {
    padding: 0.3em 0.6em;
    font-size: 0.8em;
  }
  :deep(.fc-daygrid-day-number) {
  font-size: 0.7em;
  }
}

.button-container {
  margin-top: 1.5rem; 
  text-align: right; 
}

.update-password-button {
  display: inline-flex;
  justify-content: center;
  align-items: center;
  line-height: 1;
  font-size: 12px;
  font-weight: 500;
  padding: 8px 15px;
  border-radius: 4px;
  color: #b0afaf;
  background-color: #ffffff;
  border: 1px solid #dcdfe6;
  cursor: pointer;
  text-decoration: none;
  white-space: nowrap;
  transition: .1s;
}

.update-password-button:hover {
  color: #409EFF;
  border-color: #c6e2ff;
  background-color: #ecf5ff;
}
</style>
