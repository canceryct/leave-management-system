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
const leaveForm = reactive({ leave_type_id: null, proxy_user_id: null, leave_period: 'full' });
const calendarEvents = ref([]);

const calendarOptions = ref({
  plugins: [dayGridPlugin, interactionPlugin, listPlugin],
  initialView: 'dayGridMonth',
  weekends: true,
  height: 'auto',
  events: [],
  dateClick: handleDateClick,
  eventClick: handleEventClick,
  locale: 'zh-tw',
  buttonText: { today: '今天' },
  eventDidMount: function(info) { const proxyName = info.event.extendedProps.proxy_user_name; if (proxyName) { info.el.title = `代理人：${proxyName}`; } },
  eventContent: handleEventContent,
});

// ✨ 全新版本的 handleEventContent
function handleEventContent(arg) {
  if (isMobile.value) {
    const name = arg.event.title.split(' - ')[0];
    const period = arg.event.extendedProps.leave_period;
    let newTitle = name;
    if (period === 'am') {
      newTitle += 'AM';
    } else if (period === 'pm') {
      newTitle += 'PM';
    }
    return {
      html: `<div class="fc-event-main-frame"><div class="fc-event-title-container"><div class="fc-event-title fc-sticky">${newTitle}</div></div></div>`
    };
  }
  return;
}

watch(isMobile, (isMobileValue) => {
  if (isMobileValue) {
    calendarOptions.value.initialView = 'listWeek';
    calendarOptions.value.headerToolbar = { left: 'prev,next', center: 'title', right: 'today' };
    calendarOptions.value.dayHeaderFormat = { weekday: 'short' };
  } else {
    calendarOptions.value.initialView = 'dayGridMonth';
    calendarOptions.value.headerToolbar = null;
    calendarOptions.value.dayHeaderFormat = null;
  }
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
  const existingEvent = calendarEvents.value.find(event => 
    event.start === arg.dateStr && event.extendedProps?.user_id === user.value.id
  );
  if (existingEvent) {
    ElMessage.warning('您在這天已經登記過假單了！');
    return;
  }
  selectedDate.value = arg.dateStr;
  await fetchPotentialProxies(arg.dateStr);
  isModalVisible.value = true;
}

function handleEventClick(arg) {
  const event = arg.event;
  const props = event.extendedProps;
  const title = event.title;
  const date = event.startStr;
  const proxyName = props.proxy_user_name || '未指定';

  if (props.user_id === user.value.id) {
    ElMessageBox.confirm(
      `<div><p><strong>日期：</strong> ${date}</p><p><strong>假別：</strong> ${title.split(' - ')[1] || title}</p><p><strong>代理人：</strong> ${proxyName}</p><br><p>您確定要刪除這筆假單嗎？</p></div>`,
      '假單詳情與刪除確認',
      {
        dangerouslyUseHTMLString: true,
        confirmButtonText: '確定刪除',
        cancelButtonText: '取消',
        type: 'warning',
      }
    ).then(() => {
      deleteLeaveRecord(event.id);
    }).catch(() => {
      ElMessage.info('已取消刪除操作');
    });
  } else {
    ElMessageBox.alert(
      `<div><p><strong>請假人：</strong> ${title.split(' - ')[0]}</p><p><strong>日期：</strong> ${date}</p><p><strong>假別：</strong> ${title.split(' - ')[1] || title}</p><p><strong>代理人：</strong> ${proxyName}</p></div>`,
      '假單詳情',
      {
        dangerouslyUseHTMLString: true,
        confirmButtonText: '關閉',
      }
    );
  }
}

async function handleSubmitLeave() {
  if (!leaveForm.leave_type_id || !leaveForm.proxy_user_id) { ElMessage.error('請選擇假別與代理人！'); return; }
  try {
    const { data: proxyRecords } = await supabase.from('leave_records').select('id').eq('proxy_user_id', user.value.id).eq('leave_date', selectedDate.value);
    if (proxyRecords && proxyRecords.length > 0) {
      await ElMessageBox.confirm('提醒：您當天已是其他人的代理人，確定要繼續請假嗎？', '代理人提醒', { type: 'warning' });
    }
    const { data, error } = await supabase.rpc('request_leave', { p_leave_date: selectedDate.value, p_leave_type_id: leaveForm.leave_type_id, p_proxy_user_id: leaveForm.proxy_user_id, p_leave_period: leaveForm.leave_period });
    if (error) throw error;
    if (data.success) {
      ElNotification({ title: '成功', message: data.message, type: 'success' });
      isModalVisible.value = false; Object.assign(leaveForm, { leave_type_id: null, proxy_user_id: null, leave_period: 'full' });
      await fetchLeaveRecords();
    } else { ElMessage.error(data.message); }
  } catch (error) {
    if (error.message !== 'Operation cancelled' && error !== 'cancel') { ElMessage.error('操作失敗：' + error.message); }
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

// ✨ 更新 fetchLeaveRecords 以包含 leave_period
async function fetchLeaveRecords() {
  if (!user.value) return;
  const { data, error } = await supabase.rpc('get_calendar_events');
  if (error) { console.error('Error fetching events:', error); ElMessage.error('讀取假單失敗: ' + error.message); return; }
  calendarEvents.value = data.map(record => ({
    id: record.id, 
    title: `${record.full_name || '(未知)'} - ${record.leave_type_name || '(未知)'}${record.leave_period === 'am' ? ' (AM)' : record.leave_period === 'pm' ? ' (PM)' : ''}`, 
    start: record.leave_date, 
    allDay: true,
    backgroundColor: record.user_id === user.value.id ? '#3788d8' : '#757575', 
    borderColor: record.user_id === user.value.id ? '#3788d8' : '#757575',
    extendedProps: { 
      user_id: record.user_id, 
      proxy_user_name: record.proxy_user_name,
      leave_period: record.leave_period
    }
  }));
}

async function deleteLeaveRecord(recordId) {
  const { error } = await supabase.from('leave_records').delete().eq('id', recordId);
  if (error) { ElMessage.error('刪除失敗：' + error.message); } 
  else { ElMessage.success('刪除成功！'); await fetchLeaveRecords(); }
}

async function initializePage() {
  const { data: { user: currentUser } } = await supabase.auth.getUser();
  if (!currentUser) return;
  user.value = currentUser;
  const { data: profileData } = await supabase.from('profiles').select('*').eq('id', user.value.id).single();
  userProfile.value = profileData;
  if (userProfile.value) {
    await Promise.all([ fetchLeaveRecords(), fetchLeaveTypes(), fetchPotentialProxies(new Date().toISOString().split('T')[0]) ]);
  }
}

const handleVisibilityChange = () => { if (!document.hidden) { console.log("頁面恢復可見，執行強制重新整理..."); location.reload(); } };

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
    <el-dialog v-model="isModalVisible" :title="'登記 ' + selectedDate + ' 的假單'">
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
          <el-select v-model="leaveForm.proxy_user_id" placeholder="請選擇代理人" style="width: 100%;">
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
:deep(.fc-day-past) {
  background-color: #f5f5f5;
}

@media (max-width: 768px) {
  .page-container {
    padding: 1em;
  }
  :deep(.fc .fc-toolbar-title) {
    font-size: 1.1em;
  }
  :deep(.fc-event-title) {
    font-size: 10px;
  }
  :deep(.fc-list-event) {
    padding-top: 8px;
    padding-bottom: 8px;
  }
}
</style>