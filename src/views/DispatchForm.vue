<script setup>
import { ref, reactive, onMounted, computed, watch, nextTick } from 'vue';
import { supabase } from '../supabase';
import { ElMessage } from 'element-plus';
import { ArrowLeft, ArrowRight, Rank, Delete, Plus, Camera, Loading } from '@element-plus/icons-vue';
import { useRouter } from 'vue-router';
import Sortable from 'sortablejs';
import html2canvas from 'html2canvas';

const router = useRouter();
const loading = ref(true);
const selectedDate = ref(new Date());
const isGeneratingImage = ref(false);
const formRef = ref(null);
const printAreaRef = ref(null);
const yardTableRef = ref(null);

// [修改] 新增計程車輸入框的 ref
const taxiInput = ref('');

// --- State Variables ---
const dispatchablePersonnel = ref([]);
const yardLocations = reactive([
  // ... (資料結構不變)
  { id: 1, name: '中國', cases: null, handler: null, assistant: null, vehicle: null },
  { id: 2, name: '長榮', cases: null, handler: null, assistant: null, vehicle: null },
  { id: 3, name: '東亞', cases: null, handler: null, assistant: null, vehicle: null },
  { id: 4, name: '台陽', cases: null, handler: null, assistant: null, vehicle: null },
  { id: 5, name: '環球', cases: null, handler: null, assistant: null, vehicle: null },
  { id: 6, name: '長春', cases: null, handler: null, assistant: null, vehicle: null },
  { id: 7, name: '中華', cases: null, handler: null, assistant: null, vehicle: null },
  { id: 8, name: '中央', cases: null, handler: null, assistant: null, vehicle: null },
  { id: 9, name: '弘寶', cases: null, handler: null, assistant: null, vehicle: null },
  { id: 10, name: '世邦', cases: null, handler: null, assistant: null, vehicle: null },
  { id: 11, name: '連興', cases: null, handler: null, assistant: null, vehicle: null },
  { id: 12, name: '西16', cases: null, handler: null, assistant: null, vehicle: null },
  { id: 13, name: '第一', cases: null, handler: null, assistant: null, vehicle: null },
  { id: 14, name: '陽明', cases: null, handler: null, assistant: null, vehicle: null },
  { id: 15, name: '中基', cases: null, handler: null, assistant: null, vehicle: null },
  { id: 16, name: '台基', cases: null, handler: null, assistant: null, vehicle: null },
]);

// [修改] 將 person 和 taxiNumbers 的資料型態改為陣列
const otherTasks = reactive({
  sendOfficialDocs: { driver: null },
  sendSamples: { driver: null },
  taipeiHarbor: { handler: null, assistant: null, driver: null },
  affidavit: { handler: null, assistant: null, driver: null },
  onLeave: { handlers: [], assistants: [], drivers: [] },
  otherDuties: { person: [] }, // 改為陣列
  taxiNumbers: [], // 改為陣列
});


// --- Computed Properties ---
const personnelMap = computed(() => {
  const map = new Map();
  dispatchablePersonnel.value.forEach(p => map.set(p.id, p.full_name));
  map.set('Taxi', '計程車');
  return map;
});
const groupedYardLocations = computed(() => {
  const groups = new Map();
  yardLocations.forEach(loc => {
    if (!loc.handler) return;
    const key = `${loc.handler || 'none'}-${loc.assistant || 'none'}-${loc.vehicle || 'none'}`;
    if (!groups.has(key)) {
      groups.set(key, {
        handler: personnelMap.value.get(loc.handler) || loc.handler,
        assistant: personnelMap.value.get(loc.assistant) || loc.assistant,
        vehicle: personnelMap.value.get(loc.vehicle) || loc.vehicle,
        locations: [],
      });
    }
    if (loc.name || loc.cases) {
       groups.get(key).locations.push({ name: loc.name, cases: loc.cases || 0 });
    }
  });
  return Array.from(groups.values());
});
const assignedInYards = computed(() => {
  const assigned = new Set();
  yardLocations.forEach(loc => {
    if (loc.handler && typeof loc.handler === 'string' && loc.handler.length > 20) assigned.add(loc.handler);
    if (loc.assistant && typeof loc.assistant === 'string' && loc.assistant.length > 20) assigned.add(loc.assistant);
    if (loc.vehicle && loc.vehicle !== 'Taxi' && typeof loc.vehicle === 'string' && loc.vehicle.length > 20) assigned.add(loc.vehicle);
  });
  return assigned;
});
// [修改] 更新 assignedInOtherTasks 以處理 person 陣列
const assignedInOtherTasks = computed(() => {
  const assigned = new Set();
  const tasks = [
    otherTasks.sendOfficialDocs.driver, otherTasks.sendSamples.driver,
    otherTasks.taipeiHarbor.handler, otherTasks.taipeiHarbor.assistant, otherTasks.taipeiHarbor.driver,
    otherTasks.affidavit.handler, otherTasks.affidavit.assistant, otherTasks.affidavit.driver,
    ...(otherTasks.otherDuties.person || []) // 將 person 陣列展開
  ];
  tasks.forEach(personId => {
    if (personId && typeof personId === 'string' && personId.length > 20) {
      assigned.add(personId);
    }
  });
  return assigned;
});
const baseHandlerOptions = computed(() => dispatchablePersonnel.value.filter(p => p.group_id === 2));
const baseAssistantOptions = computed(() => dispatchablePersonnel.value.filter(p => p.group_id === 2 || p.group_id === 3));
const baseDriverOptions = computed(() => dispatchablePersonnel.value.filter(p => p.group_id === 5));
const yardHandlerOptions = computed(() => baseHandlerOptions.value.filter(p => !assignedInOtherTasks.value.has(p.id)));
const yardAssistantOptions = computed(() => baseAssistantOptions.value.filter(p => !assignedInOtherTasks.value.has(p.id)));
const yardDriverOptions = computed(() => baseDriverOptions.value.filter(p => !assignedInOtherTasks.value.has(p.id)));
const yardVehicleOptions = computed(() => [{ id: 'Taxi', full_name: '計程車' },...yardDriverOptions.value]);
const otherTaskOptions = computed(() => {
  const allAssigned = new Set([...assignedInYards.value, ...assignedInOtherTasks.value]);
  return {
    handlers: baseHandlerOptions.value.filter(p => !allAssigned.has(p.id)),
    assistants: baseAssistantOptions.value.filter(p => !allAssigned.has(p.id)),
    drivers: baseDriverOptions.value.filter(p => !allAssigned.has(p.id)),
  };
});
const formattedDate = computed(() => { // 
  const date = selectedDate.value;
  if (!date) return '日期:';
  const year = date.getFullYear() - 1911;
  const month = (date.getMonth() + 1).toString().padStart(2, '0');
  const day = date.getDate().toString().padStart(2, '0');
  const period = new Date().getHours() < 12 ? '上午' : '下午';
  return `民國 ${year} 年 ${month} 月 ${day} 日 ${period}`;
});
const totalCases = computed(() => yardLocations.reduce((sum, loc) => sum + (loc.cases || 0), 0)); // 
const handlerCount = computed(() => new Set(yardLocations.map(loc => loc.handler).filter(Boolean)).size); // 
const assistantCount = computed(() => new Set(yardLocations.map(loc => loc.assistant).filter(Boolean)).size); // 
// [修改] 更新 taxiCount 計算邏輯
const taxiCount = computed(() => { // 
    const fromTable = yardLocations.filter(loc => loc.vehicle === 'Taxi').length;
    const fromInput = otherTasks.taxiNumbers.length; // 直接計算陣列長度
    return fromTable + fromInput;
});
const officialCarCount = computed(() => new Set(yardLocations.map(loc => loc.vehicle).filter(v => v && v !== 'Taxi')).size); // 

// --- Functions ---
// [新增] 計程車號標籤相關的處理函式
const handleTaxiClose = (tag) => {
  otherTasks.taxiNumbers.splice(otherTasks.taxiNumbers.indexOf(tag), 1);
};
const handleTaxiInputConfirm = () => {
  if (taxiInput.value) {
    otherTasks.taxiNumbers.push(taxiInput.value);
  }
  taxiInput.value = '';
};

// ... (其他函式保持不變)
async function generateImage() {
  if (!printAreaRef.value) return;
  isGeneratingImage.value = true;
  await nextTick();
  try {
    const canvas = await html2canvas(printAreaRef.value, { scale: 2, useCORS: true, backgroundColor: '#ffffff' });
    const image = canvas.toDataURL('image/png', 1.0);
    const link = document.createElement('a');
    link.href = image;
    link.download = `派遣表單-${formatDateToYYYYMMDD(selectedDate.value)}.png`;
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
  } catch (error) {
    console.error("產生圖片失敗:", error);
    ElMessage.error("產生圖片失敗，請檢查主控台錯誤訊息。");
  } finally {
    isGeneratingImage.value = false;
  }
}
function formatDateToYYYYMMDD(date) {
  if (!date) return null;
  const year = date.getFullYear();
  const month = (date.getMonth() + 1).toString().padStart(2, '0');
  const day = date.getDate().toString().padStart(2, '0');
  return `${year}-${month}-${day}`;
}
async function fetchOnLeavePersonnel(date) {
  const dateString = formatDateToYYYYMMDD(date);
  if (!dateString) return;
  try {
    const { data, error } = await supabase.rpc('get_on_leave_personnel', { p_date: dateString });
    if (error) throw error;
    otherTasks.onLeave.handlers = [];
    otherTasks.onLeave.assistants = [];
    otherTasks.onLeave.drivers = [];
    if (data && data.length > 0) {
      data.forEach(person => {
        if (person.group_id === 2) { otherTasks.onLeave.handlers.push(person.full_name); }
        else if (person.group_id === 3) { otherTasks.onLeave.assistants.push(person.full_name); }
        else if (person.group_id === 5) { otherTasks.onLeave.drivers.push(person.full_name); }
      });
    }
  } catch (error) { console.error('讀取休假人員列表失敗:', error); }
}
async function fetchPersonnel(date) {
  const dateString = formatDateToYYYYMMDD(date);
  if (!dateString) return;
  try {
    const { data, error } = await supabase.rpc('get_dispatchable_personnel', { p_date: dateString });
    if (error) throw error;
    dispatchablePersonnel.value = data;
  } catch (error) {
    ElMessage.error(`讀取可派遣人員列表失敗: ${error.message}`);
    dispatchablePersonnel.value = [];
  }
}
async function fetchData(date) {
  if (!date) return;
  loading.value = true;
  await Promise.all([ fetchPersonnel(date), fetchOnLeavePersonnel(date) ]);
  loading.value = false;
}
const prevDay = () => { const d = new Date(selectedDate.value); d.setDate(d.getDate() - 1); selectedDate.value = new Date(d); };
const nextDay = () => { const d = new Date(selectedDate.value); d.setDate(d.getDate() + 1); selectedDate.value = new Date(d); };
let nextLocationId = 100;
function addLocation() {
  yardLocations.push({ id: nextLocationId++, name: '', cases: null, handler: null, assistant: null, vehicle: null });
}
function deleteLocation(index) {
  yardLocations.splice(index, 1);
}
const initSortable = () => {
  const tbody = yardTableRef.value?.$el.querySelector('.el-table__body-wrapper tbody');
  if (tbody) {
    Sortable.create(tbody, {
      handle: '.drag-handle',
      animation: 150,
      onEnd: ({ newIndex, oldIndex }) => {
        const currentRow = yardLocations.splice(oldIndex, 1)[0];
        yardLocations.splice(newIndex, 0, currentRow);
      },
    });
  }
};

watch(selectedDate, (newDate) => { fetchData(newDate); });
onMounted(() => {
  fetchData(selectedDate.value).then(() => {
    nextTick(() => { initSortable(); });
  });
});
</script>

<template>
  <div class="dispatch-form-container">
    <div class="form-capture-area" ref="formRef">
      <div class="page-header">
        <el-button @click="router.push('/dashboard')" class="no-print">返回月曆</el-button>
        <div class="date-selector no-print">
          <el-button :icon="ArrowLeft" @click="prevDay" circle />
          <el-date-picker v-model="selectedDate" type="date" :editable="false" style="width: 180px; margin: 0 1rem;" />
          <el-button :icon="ArrowRight" @click="nextDay" circle />
        </div>
        <div class="date-display">日期: {{ formattedDate }}</div>
        <div class="total-cases">總件數：{{ totalCases }} 件</div>
      </div>
      <div class="form-content" v-loading="loading">
        <div class="main-table-wrapper">
          <el-table :data="yardLocations" row-key="id" border style="width: 100%" size="small" ref="yardTableRef">
            <el-table-column width="55" label="排序" align="center" class-name="no-print">
              <template #default>
                <el-icon class="drag-handle" title="按住此處拖曳排序"><Rank /></el-icon>
              </template>
            </el-table-column>
            <el-table-column label="櫃場" width="110">
              <template #default="scope"><el-input v-model="scope.row.name" placeholder="輸入地點" size="small" /></template>
            </el-table-column>
            <el-table-column label="件數" width="90">
              <template #default="scope"><el-input-number v-model="scope.row.cases" :min="0" controls-position="right" size="small" style="width: 100%" /></template>
            </el-table-column>
            <el-table-column label="承辦人" min-width="150">
              <template #default="scope"><el-select v-model="scope.row.handler" placeholder="選擇" filterable allow-create clearable style="width: 100%"><el-option v-for="p in yardHandlerOptions" :key="p.id" :label="p.full_name" :value="p.id" /></el-select></template>
            </el-table-column>
            <el-table-column label="助理" min-width="150">
              <template #default="scope"><el-select v-model="scope.row.assistant" placeholder="選擇" filterable allow-create clearable style="width: 100%"><el-option v-for="p in yardAssistantOptions" :key="p.id" :label="p.full_name" :value="p.id" /></el-select></template>
            </el-table-column>
            <el-table-column label="車" min-width="150">
              <template #default="scope"><el-select v-model="scope.row.vehicle" placeholder="選擇" filterable allow-create clearable style="width: 100%"><el-option v-for="v in yardVehicleOptions" :key="v.id" :label="v.full_name" :value="v.id" /></el-select></template>
            </el-table-column>
            <el-table-column width="55" label="操作" align="center" class-name="no-print">
              <template #default="scope">
                <el-button :icon="Delete" @click="deleteLocation(scope.$index)" type="danger" size="small" circle plain />
              </template>
            </el-table-column>
          </el-table>
          <el-button @click="addLocation" :icon="Plus" style="width: 100%; margin-top: 10px;" class="no-print">新增櫃場地點</el-button>
        </div>
        <div class="other-tasks-wrapper">
          <el-card shadow="never" class="other-tasks-card">
            <div class="other-tasks-grid">
              <div class="task-item"><span class="task-label">送公文司機:</span><el-select v-model="otherTasks.sendOfficialDocs.driver" size="small" placeholder="選擇司機" filterable allow-create clearable><el-option v-for="p in otherTaskOptions.drivers" :key="p.id" :label="p.full_name" :value="p.id" /></el-select></div>
              <div class="task-item"><span class="task-label">送樣品司機:</span><el-select v-model="otherTasks.sendSamples.driver" size="small" placeholder="選擇司機" filterable allow-create clearable><el-option v-for="p in otherTaskOptions.drivers" :key="p.id" :label="p.full_name" :value="p.id" /></el-select></div>
              <div class="task-item-group"><div class="task-label full-width">台北港</div><div>承辦人:<el-select v-model="otherTasks.taipeiHarbor.handler" size="small" placeholder="選擇" filterable allow-create clearable><el-option v-for="p in otherTaskOptions.handlers" :key="p.id" :label="p.full_name" :value="p.id" /></el-select></div><div>助理:<el-select v-model="otherTasks.taipeiHarbor.assistant" size="small" placeholder="選擇" filterable allow-create clearable><el-option v-for="p in otherTaskOptions.assistants" :key="p.id" :label="p.full_name" :value="p.id" /></el-select></div><div>司機:<el-select v-model="otherTasks.taipeiHarbor.driver" size="small" placeholder="選擇" filterable allow-create clearable><el-option v-for="p in otherTaskOptions.drivers" :key="p.id" :label="p.full_name" :value="p.id" /></el-select></div></div>
              <div class="task-item-group"><div class="task-label full-width">具結</div><div>承辦人:<el-select v-model="otherTasks.affidavit.handler" size="small" placeholder="選擇" filterable allow-create clearable><el-option v-for="p in otherTaskOptions.handlers" :key="p.id" :label="p.full_name" :value="p.id" /></el-select></div><div>助理:<el-select v-model="otherTasks.affidavit.assistant" size="small" placeholder="選擇" filterable allow-create clearable><el-option v-for="p in otherTaskOptions.assistants" :key="p.id" :label="p.full_name" :value="p.id" /></el-select></div><div>司機:<el-select v-model="otherTasks.affidavit.driver" size="small" placeholder="選擇" filterable allow-create clearable><el-option v-for="p in otherTaskOptions.drivers" :key="p.id" :label="p.full_name" :value="p.id" /></el-select></div></div>
              <div class="task-item-group vertical-group"><div class="task-label full-width">休假</div><div class="leave-item" v-if="otherTasks.onLeave.handlers.length > 0">承辦人: {{ otherTasks.onLeave.handlers.join('、') }}</div><div class="leave-item" v-if="otherTasks.onLeave.assistants.length > 0">助理: {{ otherTasks.onLeave.assistants.join('、') }}</div><div class="leave-item" v-if="otherTasks.onLeave.drivers.length > 0">司機: {{ otherTasks.onLeave.drivers.join('、') }}</div><div class="leave-item" v-if="otherTasks.onLeave.handlers.length === 0 && otherTasks.onLeave.assistants.length === 0 && otherTasks.onLeave.drivers.length === 0">無相關組別人員休假</div></div>

              <div class="task-item-group">
                <div class="task-label full-width">其他公務</div>
                <div>放單人員:
                  <el-select v-model="otherTasks.otherDuties.person" multiple size="small" placeholder="選擇" filterable clearable>
                    <el-option v-for="p in otherTaskOptions.assistants" :key="p.id" :label="p.full_name" :value="p.id" />
                  </el-select>
                </div>
              </div>

              <div class="task-item full-width taxi-input-container">
                <span class="task-label">計程車號:</span>
                <div class="tag-input-wrapper">
                    <el-tag
                      v-for="tag in otherTasks.taxiNumbers"
                      :key="tag"
                      closable
                      :disable-transitions="false"
                      @close="handleTaxiClose(tag)"
                      style="margin-right: 5px;"
                    >
                      {{ tag }}
                    </el-tag>
                    <el-input
                      v-model="taxiInput"
                      size="small"
                      placeholder="輸入後按 Enter"
                      @keyup.enter="handleTaxiInputConfirm"
                      style="width: 120px;"
                    />
                </div>
              </div>
            </div>
          </el-card>
        </div>
      </div>
      <div class="form-footer"> <div>臨場查驗派遣統計：</div>
        <div>承辦人：<span>{{ handlerCount }}</span> 人</div> <div>助理：<span>{{ assistantCount }}</span> 人</div> <div>計程車：<span>{{ taxiCount }}</span> 台</div> <div>公務車：<span>{{ officialCarCount }}</span> 台</div> </div>
    </div>
    <div class="generate-image-fab no-print" @click="generateImage" title="將表單另存為圖片">
      <el-icon v-if="!isGeneratingImage"><Camera /></el-icon>
      <el-icon v-else class="is-loading"><Loading /></el-icon>
    </div>
  </div>


  <div class="print-area" ref="printAreaRef">
    <div class="print-header">
      <div class="print-title">基隆港辦事處臨場查驗派遣單</div>
      <div class="print-date">日期: {{ formattedDate }}</div>
      <div class="print-total-cases">總件數: {{ totalCases }} 件</div>
    </div>
    <div class="print-content">
      <div class="print-main-table">
        <table class="main-table-body">
          <thead>
            <tr>
              <th>櫃場</th>
              <th>件數</th>
              <th>承辦人</th>
              <th>助理</th>
              <th>車</th>
            </tr>
          </thead>
          <tbody>
            <template v-for="(group, index) in groupedYardLocations" :key="index">
              <tr v-for="(loc, locIndex) in group.locations" :key="locIndex">
                <td>{{ loc.name }}</td>
                <td>{{ loc.cases }}</td>
                <td v-if="locIndex === 0" :rowspan="group.locations.length" class="merged-cell">{{ group.handler }}</td>
                <td v-if="locIndex === 0" :rowspan="group.locations.length" class="merged-cell">{{ group.assistant }}</td>
                <td v-if="locIndex === 0" :rowspan="group.locations.length" class="merged-cell">{{ group.vehicle }}</td>
              </tr>
            </template>
            <tr v-if="groupedYardLocations.length === 0">
              <td colspan="5" style="text-align: center; padding: 20px;">尚無派遣資料</td>
            </tr>
          </tbody>
        </table>
      </div>
      <div class="print-other-tasks">
        <div class="task-grid">
            <div class="task-row"><span class="label">送公文司機:</span> <span class="value">{{ personnelMap.get(otherTasks.sendOfficialDocs.driver) || '' }}</span></div>
            <div class="task-row"><span class="label">送樣品司機:</span> <span class="value">{{ personnelMap.get(otherTasks.sendSamples.driver) || '' }}</span></div>

            <div class="task-group">
                <div class="group-title">台北港</div>
                <div class="task-row"><span class="label">承辦人:</span> <span class="value">{{ personnelMap.get(otherTasks.taipeiHarbor.handler) || '' }}</span></div>
                <div class="task-row"><span class="label">助理:</span> <span class="value">{{ personnelMap.get(otherTasks.taipeiHarbor.assistant) || '' }}</span></div>
                <div class="task-row"><span class="label">司機:</span> <span class="value">{{ personnelMap.get(otherTasks.taipeiHarbor.driver) || '' }}</span></div>
            </div>

            <div class="task-group">
                <div class="group-title">具結</div>
                <div class="task-row"><span class="label">承辦人:</span> <span class="value">{{ personnelMap.get(otherTasks.affidavit.handler) || '' }}</span></div>
                <div class="task-row"><span class="label">助理:</span> <span class="value">{{ personnelMap.get(otherTasks.affidavit.assistant) || '' }}</span></div>
                <div class="task-row"><span class="label">司機:</span> <span class="value">{{ personnelMap.get(otherTasks.affidavit.driver) || '' }}</span></div>
            </div>

            <div class="task-group">
                <div class="group-title">休假</div>
                <div class="task-row" v-if="otherTasks.onLeave.handlers.length > 0"><span class="label">承辦人:</span> <span class="value">{{ otherTasks.onLeave.handlers.join('、') }}</span></div>
                <div class="task-row" v-if="otherTasks.onLeave.assistants.length > 0"><span class="label">助理:</span> <span class="value">{{ otherTasks.onLeave.assistants.join('、') }}</span></div>
                <div class="task-row" v-if="otherTasks.onLeave.drivers.length > 0"><span class="label">司機:</span> <span class="value">{{ otherTasks.onLeave.drivers.join('、') }}</span></div>
            </div>
             <div class="task-group">
                <div class="group-title">其他公務</div>
                <div class="task-row">
                  <span class="label">放單人員:</span>
                  <span class="value">{{ (otherTasks.otherDuties.person || []).map(id => personnelMap.get(id) || id).join('、') }}</span>
                </div>
            </div>
            <div class="task-row full-width">
              <span class="label">計程車號:</span>
              <span class="value">{{ otherTasks.taxiNumbers.join('、') }}</span>
            </div>
        </div>
      </div>
    </div>
    <div class="print-footer">
      <span>臨場查驗派遣統計：</span>
      <span>承辦人: {{ handlerCount }} 人</span>
      <span>助理: {{ assistantCount }} 人</span>
      <span>計程車: {{ taxiCount }} 台</span>
      <span>公務車: {{ officialCarCount }} 台</span>
    </div>
  </div>
</template>

<style scoped>
/* --- 操作介面樣式 --- */
.dispatch-form-container { padding: 2em; max-width: 1600px; margin: 0 auto; }
.form-capture-area { background-color: #fff; padding: 1.5rem; border: 1px solid #ddd; border-radius: 8px; }
.page-header { display: flex; justify-content: space-between; align-items: center; margin-bottom: 2rem; }
.date-selector { display: flex; align-items: center; }
.date-display { font-size: 1.2rem; font-weight: 500; color: #606266; }
.total-cases { font-size: 1.2rem; font-weight: 500; }
.form-content { display: flex; gap: 1.5rem; }
.main-table-wrapper { flex: 3; }
.other-tasks-wrapper { flex: 1; min-width: 320px; }
:deep(.el-table) { font-size: 13px; }
:deep(.el-table th.el-table__cell) { background-color: #f5f7fa; }
:deep(.el-table td.el-table__cell), :deep(.el-table th.el-table__cell) { padding: 6px; }
.drag-handle { cursor: grab; font-size: 18px; }
.drag-handle:active { cursor: grabbing; }
.other-tasks-grid { display: flex; flex-direction: column; gap: 12px; }
.task-item, .task-item-group { display: flex; flex-wrap: wrap; align-items: center; gap: 8px; font-size: 14px; }
.task-label { font-weight: 500; white-space: nowrap; }
.full-width { width: 100%; }
.task-item-group > div:not(.task-label) { flex: 1; min-width: 120px; }
.form-footer {
  margin-top: 1.5rem; padding: 1rem; border: 1px solid #ddd;
  font-size: 1.1rem; font-weight: 500; display: flex; flex-wrap: wrap; gap: 1.5rem;
  background-color: #f5f7fa; border-radius: 4px;
}
.form-footer > div { display: flex; align-items: center; gap: 0.5rem; }
.form-footer span { font-weight: bold; color: #409EFF; font-size: 1.2rem; }
.generate-image-fab {
  position: fixed; bottom: 30px; right: 30px; width: 50px; height: 50px;
  background-color: #67C23A; color: white; border-radius: 50%;
  display: flex; justify-content: center; align-items: center;
  font-size: 24px; cursor: pointer; box-shadow: 0 2px 8px rgba(0,0,0,0.2);
  transition: all 0.3s ease; z-index: 1000;
}
.generate-image-fab:hover { transform: scale(1.1); }
/* [新增] 計程車標籤輸入UI的樣式 */
.taxi-input-container {
  display: flex;
  align-items: flex-start;
}
.tag-input-wrapper {
  flex: 1;
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 5px;
}
@media (max-width: 1200px) {
  .form-content { flex-direction: column; }
  .other-tasks-wrapper { min-width: 100%; }
}

/* --- 列印專用區塊的樣式 --- */
.print-area {
  font-family: 'Microsoft JhengHei', '微軟正黑體', sans-serif;
  position: absolute;
  left: -9999px;
  top: 0;
  width: 1000px;
  background: #fff;
  padding: 40px;
  color: #000;
  font-size: 14px;
  border: 1px solid #ccc;
}
.print-header { text-align: center; margin-bottom: 20px; position: relative; }
.print-title { font-size: 24px; font-weight: bold; }
.print-date, .print-total-cases { position: absolute; bottom: 0; font-size: 14px; }
.print-date { left: 0; }
.print-total-cases { right: 0; }
.print-content { display: flex; gap: 20px; border-top: 2px solid #000; border-bottom: 2px solid #000; padding: 10px 0; }
.print-main-table { flex: 2; }
.print-other-tasks { flex: 1; border-left: 1px solid #999; padding-left: 20px; }
.main-table-body { width: 100%; border-collapse: collapse; }
.main-table-body th, .main-table-body td { border: 1px solid #999; padding: 8px; text-align: center; vertical-align: middle; }
.main-table-body th { background-color: #f2f2f2; font-weight: bold; }
.main-table-body td.merged-cell { vertical-align: middle; }
.task-grid { display: flex; flex-direction: column; gap: 12px; }
.task-group { border: 1px solid #ccc; padding: 8px; border-radius: 4px; }
.group-title { font-weight: bold; margin-bottom: 8px; border-bottom: 1px solid #eee; padding-bottom: 4px; }
.task-row { display: flex; }
.task-row .label { font-weight: 500; margin-right: 8px; white-space: nowrap; }
.task-row .value { word-break: break-all; }
.print-footer { margin-top: 15px; font-size: 14px; font-weight: 500; display: flex; gap: 20px; }
</style>