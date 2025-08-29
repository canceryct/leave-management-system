<script setup>
import { ref, reactive, onMounted, computed, watch, nextTick } from 'vue';
import { supabase } from '../supabase';
import { ElMessage, ElMessageBox } from 'element-plus';
// [修改] 引入 Share 圖示
import { ArrowLeft, ArrowRight, Rank, Delete, Plus, Camera, Loading, Share } from '@element-plus/icons-vue';
import { useRouter } from 'vue-router';
import Sortable from 'sortablejs';
import html2canvas from 'html2canvas';

const router = useRouter();
const loading = ref(true);
const selectedDate = ref(new Date());
const selectedPeriod = ref('下午');
const isGeneratingImage = ref(false); // 共用一個載入狀態
const formRef = ref(null);
const printAreaRef = ref(null);
const yardTableRef = ref(null);
const taxiInput = ref('');

const predefinedTaxis = [
  'TDU-1010', 'TDU-2062', 'TDU-1337', 'TAX-856', 'TAW-558', 'TDU-1502',
  '912-L8', 'TDU-2655', 'TEA-0519', '093-2E', 'TDU-1612', 'TDU-2958',
  'TDA-1193', 'TDU-2290'
];
predefinedTaxis.sort();


// --- State Variables ---
const dispatchablePersonnel = ref([]);
const yardLocations = reactive([]);
const otherTasks = reactive({
  sendOfficialDocs: { driver: null },
  sendSamples: { driver: null },
  taipeiHarbor: { handler: null, assistant: null, driver: null },
  affidavit: { handler: null, assistant: null, driver: null },
  onLeave: {
    handlers: [],
    assistants: [],
    drivers: [],
    manualOnLeave: [],
  },
  otherDuties: {
    person: [],
    otherDutiesPersonnel: [],
  },
  taxiNumbers: [],
});

const initialYardLocationsTemplate = [
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
];
const initialOtherTasksTemplate = {
  sendOfficialDocs: { driver: null },
  sendSamples: { driver: null },
  taipeiHarbor: { handler: null, assistant: null, driver: null },
  affidavit: { handler: null, assistant: null, driver: null },
  onLeave: { handlers: [], assistants: [], drivers: [], manualOnLeave: [] },
  otherDuties: { person: [], otherDutiesPersonnel: [] },
  taxiNumbers: [],
};


// --- Computed Properties (此區塊無變動) ---
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
const assignedInStrictTasks = computed(() => {
  const assigned = new Set();
  const tasks = [
    otherTasks.taipeiHarbor.handler,
    otherTasks.taipeiHarbor.assistant,
    otherTasks.taipeiHarbor.driver,
    otherTasks.affidavit.handler,
    otherTasks.affidavit.assistant,
    otherTasks.affidavit.driver,
    ...(otherTasks.otherDuties.person || []),
    ...(otherTasks.otherDuties.otherDutiesPersonnel || []),
    ...(otherTasks.onLeave.manualOnLeave || []),
  ];
  tasks.forEach(personId => {
    if (personId && typeof personId === 'string' && personId.length > 20) {
      assigned.add(personId);
    }
  });
  return assigned;
});
const assignedInSemiStrictTasks = computed(() => {
  const assigned = new Set();
  if (otherTasks.sendOfficialDocs.driver) assigned.add(otherTasks.sendOfficialDocs.driver);
  if (otherTasks.sendSamples.driver) assigned.add(otherTasks.sendSamples.driver);
  return assigned;
});
const baseHandlerOptions = computed(() => dispatchablePersonnel.value.filter(p => p.group_id === 2));
const baseAssistantOptions = computed(() => dispatchablePersonnel.value.filter(p => p.group_id === 2 || p.group_id === 3));
const baseDriverOptions = computed(() => dispatchablePersonnel.value.filter(p => p.group_id === 5));
const yardHandlerOptions = computed(() => baseHandlerOptions.value.filter(p => !assignedInStrictTasks.value.has(p.id)));
const yardAssistantOptions = computed(() => baseAssistantOptions.value.filter(p => !assignedInStrictTasks.value.has(p.id)));
const yardDriverOptions = computed(() => baseDriverOptions.value.filter(p => !assignedInStrictTasks.value.has(p.id)));
const yardVehicleOptions = computed(() => [{ id: 'Taxi', full_name: '計程車' },...yardDriverOptions.value]);
const groupedYardHandlerOptions = computed(() => {
    if (yardHandlerOptions.value.length > 0) {
        return [{ label: '承辦人', options: yardHandlerOptions.value }];
    }
    return [];
});
const groupedYardAssistantOptions = computed(() => {
  const inspectionAssistants = yardAssistantOptions.value.filter(p => p.group_id === 2);
  const samplingAssistants = yardAssistantOptions.value.filter(p => p.group_id === 3);

  const groups = [];
  if (inspectionAssistants.length > 0) {
    groups.push({ label: '臨場查驗組', options: inspectionAssistants });
  }
  if (samplingAssistants.length > 0) {
    groups.push({ label: '取樣助理組', options: samplingAssistants });
  }
  return groups;
});
const groupedYardVehicleOptions = computed(() => {
    const taxis = yardVehicleOptions.value.filter(v => v.id === 'Taxi');
    const drivers = yardVehicleOptions.value.filter(v => v.id !== 'Taxi');
    const groups = [];
    if (taxis.length > 0) {
        groups.push({ label: '計程車', options: taxis });
    }
    if (drivers.length > 0) {
        groups.push({ label: '公務車司機', options: drivers });
    }
    return groups;
});
const selectedInYards = computed(() => {
    const selected = new Set();
    yardLocations.forEach(loc => {
        if (loc.handler) selected.add(loc.handler);
        if (loc.assistant) selected.add(loc.assistant);
        if (loc.vehicle && loc.vehicle !== 'Taxi') selected.add(loc.vehicle);
    });
    return selected;
});
const otherTaskOptions = computed(() => {
  const allAssigned = new Set([
      ...assignedInYards.value,
      ...assignedInStrictTasks.value,
      ...assignedInSemiStrictTasks.value
    ]);
  return {
    handlers: baseHandlerOptions.value.filter(p => !allAssigned.has(p.id)),
    assistants: baseAssistantOptions.value.filter(p => !allAssigned.has(p.id)),
    drivers: baseDriverOptions.value.filter(p => !allAssigned.has(p.id)),
  };
});
const semiStrictTaskDriverOptions = computed(() => {
    const assignedInAnyOtherTask = new Set([
        ...assignedInStrictTasks.value,
        ...assignedInSemiStrictTasks.value
    ]);
    return baseDriverOptions.value.filter(p => !assignedInAnyOtherTask.has(p.id));
});
const groupedOtherTaskAssistants = computed(() => {
    const availableAssistants = otherTaskOptions.value.assistants;
    const inspectionAssistants = availableAssistants.filter(p => p.group_id === 2);
    const samplingAssistants = availableAssistants.filter(p => p.group_id === 3);

    const groups = [];
    if (inspectionAssistants.length > 0) {
        groups.push({ label: '臨場查驗組', options: inspectionAssistants });
    }
    if (samplingAssistants.length > 0) {
        groups.push({ label: '取樣助理組', options: samplingAssistants });
    }
    return groups;
});
const manualLeaveOptions = computed(() => {
    const allAssigned = new Set([
      ...assignedInYards.value,
      ...assignedInStrictTasks.value,
      ...assignedInSemiStrictTasks.value
    ]);
    const availablePersonnel = dispatchablePersonnel.value.filter(p => !allAssigned.has(p.id));
    const handlers = availablePersonnel.filter(p => p.group_id === 2 && (!p.job_title || !p.job_title.includes('助理')));
    const assistants = availablePersonnel.filter(p => p.group_id === 3 || (p.group_id === 2 && p.job_title && p.job_title.includes('助理')));
    const drivers = availablePersonnel.filter(p => p.group_id === 5);
    const groups = [];
    if (handlers.length > 0) groups.push({ label: '承辦人', options: handlers });
    if (assistants.length > 0) groups.push({ label: '助理', options: assistants });
    if (drivers.length > 0) groups.push({ label: '司機', options: drivers });
    return groups;
});
const allOnLeaveHandlers = computed(() => {
    const manual = (otherTasks.onLeave.manualOnLeave || [])
        .map(id => dispatchablePersonnel.value.find(p => p.id === id))
        .filter(p => p && p.group_id === 2 && (!p.job_title || !p.job_title.includes('助理')))
        .map(p => p.full_name);
    return [...new Set([...otherTasks.onLeave.handlers, ...manual])];
});
const allOnLeaveAssistants = computed(() => {
    const manual = (otherTasks.onLeave.manualOnLeave || [])
        .map(id => dispatchablePersonnel.value.find(p => p.id === id))
        .filter(p => p && (p.group_id === 3 || (p.group_id === 2 && p.job_title && p.job_title.includes('助理'))))
        .map(p => p.full_name);
    return [...new Set([...otherTasks.onLeave.assistants, ...manual])];
});
const allOnLeaveDrivers = computed(() => {
    const manual = (otherTasks.onLeave.manualOnLeave || [])
        .map(id => dispatchablePersonnel.value.find(p => p.id === id))
        .filter(p => p && p.group_id === 5)
        .map(p => p.full_name);
    return [...new Set([...otherTasks.onLeave.drivers, ...manual])];
});
const formattedDate = computed(() => {
  const date = selectedDate.value;
  if (!date) return '';
  const year = date.getFullYear() - 1911;
  const month = (date.getMonth() + 1).toString().padStart(2, '0');
  const day = date.getDate().toString().padStart(2, '0');
  return `${year}年${month}月${day}日 ${selectedPeriod.value}`;
});
const totalCases = computed(() => yardLocations.reduce((sum, loc) => sum + (loc.cases || 0), 0));
const handlerCount = computed(() => new Set(yardLocations.map(loc => loc.handler).filter(Boolean)).size);
const assistantCount = computed(() => new Set(yardLocations.map(loc => loc.assistant).filter(Boolean)).size);
const taxiCount = computed(() => {
    return otherTasks.taxiNumbers.length;
});
const officialCarCount = computed(() => new Set(yardLocations.map(loc => loc.vehicle).filter(v => v && v !== 'Taxi')).size);


// --- Functions ---

// [新增] 產生 Canvas 的核心函式
async function createCanvas() {
  if (!printAreaRef.value) return null;
  await nextTick();
  return await html2canvas(printAreaRef.value, {
    scale: 2,
    useCORS: true,
    backgroundColor: '#ffffff',
  });
}

// [新增] 下載圖片的函式
function downloadCanvas(canvas) {
  const image = canvas.toDataURL('image/png', 1.0);
  const link = document.createElement('a');
  link.href = image;
  link.download = `派遣表單-${formatDateToYYYYMMDD(selectedDate.value)}.png`;
  document.body.appendChild(link);
  link.click();
  document.body.removeChild(link);
}

// [修改] 原有的 generateImage 函式現在專注於「儲存」
async function generateImage() {
  isGeneratingImage.value = true;
  try {
    const canvas = await createCanvas();
    if (canvas) {
      downloadCanvas(canvas);
    }
  } catch (error) {
    console.error("產生圖片失敗:", error);
    ElMessage.error("產生圖片失敗，請檢查主控台錯誤訊息。");
  } finally {
    isGeneratingImage.value = false;
  }
}

// [新增] Web Share API 的分享函式
async function shareImage() {
  isGeneratingImage.value = true;
  let canvas;
  try {
    canvas = await createCanvas();
    if (!canvas) throw new Error('Canvas 產生失敗');

    // 將 Canvas 轉為 Blob 物件
    const blob = await new Promise(resolve => canvas.toBlob(resolve, 'image/png'));
    const file = new File([blob], `派遣表單-${formatDateToYYYYMMDD(selectedDate.value)}.png`, { type: 'image/png' });

    // 檢查瀏覽器是否支援 Web Share API
    if (navigator.share && navigator.canShare({ files: [file] })) {
      await navigator.share({
        title: `派遣表單 ${formatDateToYYYYMMDD(selectedDate.value)}`,
        text: `${formattedDate.value} 的派遣表單`,
        files: [file],
      });
    } else {
      // 不支援，則降級為下載
      ElMessage.info('您的瀏覽器不支援直接分享，已改為下載圖片。');
      downloadCanvas(canvas);
    }
  } catch (error) {
    // 如果使用者取消分享，會觸發 AbortError，我們不視為錯誤
    if (error.name === 'AbortError') {
      console.log('使用者取消了分享');
    } else {
      console.error("分享或產生圖片失敗:", error);
      ElMessage.error("分享失敗，已改為下載圖片。");
      // 如果分享過程出錯，但 canvas 已產生，仍提供下載
      if (canvas) {
        downloadCanvas(canvas);
      }
    }
  } finally {
    isGeneratingImage.value = false;
  }
}


let debounceTimer = null;
function saveDraft() {
    const draftKey = `dispatchFormDraft_${formatDateToYYYYMMDD(selectedDate.value)}`;
    const draftData = {
        yardLocations: JSON.parse(JSON.stringify(yardLocations)),
        otherTasks: JSON.parse(JSON.stringify(otherTasks)),
        selectedPeriod: selectedPeriod.value,
    };
    localStorage.setItem(draftKey, JSON.stringify(draftData));
}
function loadDraft() {
    const draftKey = `dispatchFormDraft_${formatDateToYYYYMMDD(selectedDate.value)}`;
    const draftData = localStorage.getItem(draftKey);

    if (draftData) {
        ElMessageBox.confirm(
            '偵測到此日期有暫存草稿，是否要載入？',
            '提示',
            {
                confirmButtonText: '載入草稿',
                cancelButtonText: '忽略',
                type: 'info',
            }
        ).then(() => {
            const parsedData = JSON.parse(draftData);
            yardLocations.splice(0, yardLocations.length, ...parsedData.yardLocations);
            Object.assign(otherTasks, parsedData.otherTasks);
            selectedPeriod.value = parsedData.selectedPeriod || '下午';
            ElMessage.success('草稿已成功載入');
        }).catch(() => {
            resetFormToInitialState();
            ElMessage.info('已忽略草稿，載入新表單');
        });
    } else {
        resetFormToInitialState();
    }
}
function clearDraft() {
    const draftKey = `dispatchFormDraft_${formatDateToYYYYMMDD(selectedDate.value)}`;
    if (localStorage.getItem(draftKey)) {
        ElMessageBox.confirm(
            '確定要清除本日期的暫存草稿嗎？此操作無法復原。',
            '警告',
            {
                confirmButtonText: '確定清除',
                cancelButtonText: '取消',
                type: 'warning',
            }
        ).then(() => {
            localStorage.removeItem(draftKey);
            resetFormToInitialState();
            ElMessage.success('本日草稿已清除');
        }).catch(() => {});
    } else {
        ElMessage.info('目前沒有可清除的草稿');
    }
}
function resetFormToInitialState() {
    yardLocations.splice(0, yardLocations.length, ...JSON.parse(JSON.stringify(initialYardLocationsTemplate)));
    Object.assign(otherTasks, JSON.parse(JSON.stringify(initialOtherTasksTemplate)));
    fetchOnLeavePersonnel(selectedDate.value);
}
const handleTaxiClose = (tag) => {
  otherTasks.taxiNumbers.splice(otherTasks.taxiNumbers.indexOf(tag), 1);
};
const handleTaxiInputConfirm = () => {
  if (taxiInput.value) {
    if (!otherTasks.taxiNumbers.includes(taxiInput.value)) {
        otherTasks.taxiNumbers.push(taxiInput.value);
    }
  }
  taxiInput.value = '';
};
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
        if (person.group_id === 2 || person.group_id === 3) {
            if (person.job_title && person.job_title.includes('助理')) {
                 otherTasks.onLeave.assistants.push(person.full_name);
            } else {
                 otherTasks.onLeave.handlers.push(person.full_name);
            }
        }
        else if (person.group_id === 5) {
             otherTasks.onLeave.drivers.push(person.full_name);
        }
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


watch([yardLocations, otherTasks, selectedPeriod], () => {
    clearTimeout(debounceTimer);
    debounceTimer = setTimeout(() => {
        saveDraft();
    }, 500);
}, { deep: true });

watch(selectedDate, async (newDate) => {
    loading.value = true;
    await fetchPersonnel(newDate);
    await fetchOnLeavePersonnel(newDate);
    loadDraft();
    loading.value = false;
});

onMounted(() => {
  fetchData(selectedDate.value).then(() => {
    loadDraft();
    nextTick(() => { initSortable(); });
  });
});
</script>

<template>
  <div class="dispatch-form-container">
    <div class="form-capture-area" ref="formRef">
      <div class="page-header">
        <div class="header-left">
          <el-button @click="router.push('/dashboard')" class="no-print">返回月曆</el-button>
          <el-button @click="clearDraft" type="danger" plain class="no-print">清除本日草稿</el-button>
        </div>
        <div class="date-selector no-print">
          <el-button :icon="ArrowLeft" @click="prevDay" circle title="前一天" />
          <el-date-picker v-model="selectedDate" type="date" :editable="false" style="width: 180px; margin: 0 1rem;" />
          <el-button :icon="ArrowRight" @click="nextDay" circle title="後一天" />
          <el-radio-group v-model="selectedPeriod" style="margin-left: 1.5rem;">
            <el-radio-button label="上午" />
            <el-radio-button label="下午" />
          </el-radio-group>
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
            <el-table-column label="承辦人" min-width="140">
              <template #default="scope">
                <el-select v-model="scope.row.handler" placeholder="選擇" filterable allow-create clearable style="width: 100%">
                    <el-option-group
                      v-for="group in groupedYardHandlerOptions"
                      :key="group.label"
                      :label="group.label">
                      <el-option
                        v-for="p in group.options"
                        :key="p.id"
                        :label="p.full_name"
                        :value="p.id"
                        :class="{ 'already-in-use': selectedInYards.has(p.id) }"
                      />
                    </el-option-group>
                </el-select>
              </template>
            </el-table-column>
            <el-table-column label="助理" min-width="140">
              <template #default="scope">
                <el-select v-model="scope.row.assistant" placeholder="選擇" filterable allow-create clearable style="width: 100%">
                    <el-option-group
                      v-for="group in groupedYardAssistantOptions"
                      :key="group.label"
                      :label="group.label">
                      <el-option
                        v-for="p in group.options"
                        :key="p.id"
                        :label="p.full_name"
                        :value="p.id"
                        :class="{ 'already-in-use': selectedInYards.has(p.id) }"
                      />
                    </el-option-group>
                </el-select>
              </template>
            </el-table-column>
            <el-table-column label="車" min-width="140">
              <template #default="scope">
                <el-select v-model="scope.row.vehicle" placeholder="選擇" filterable allow-create clearable style="width: 100%">
                    <el-option-group
                      v-for="group in groupedYardVehicleOptions"
                      :key="group.label"
                      :label="group.label">
                      <el-option
                        v-for="v in group.options"
                        :key="v.id"
                        :label="v.full_name"
                        :value="v.id"
                        :class="{ 'already-in-use': selectedInYards.has(v.id) && v.id !== 'Taxi' }"
                      />
                    </el-option-group>
                </el-select>
              </template>
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
              <div class="task-item">
                <span class="task-label">送公文司機:</span>
                <el-select v-model="otherTasks.sendOfficialDocs.driver" size="small" placeholder="選擇司機" filterable allow-create clearable>
                  <el-option v-for="p in semiStrictTaskDriverOptions" :key="p.id" :label="p.full_name" :value="p.id" />
                </el-select>
              </div>
              <div class="task-item">
                <span class="task-label">送樣品司機:</span>
                <el-select v-model="otherTasks.sendSamples.driver" size="small" placeholder="選擇司機" filterable allow-create clearable>
                  <el-option v-for="p in semiStrictTaskDriverOptions" :key="p.id" :label="p.full_name" :value="p.id" />
                </el-select>
              </div>
              <div class="task-item-group"><div class="task-label full-width">台北港</div><div>承辦人:<el-select v-model="otherTasks.taipeiHarbor.handler" size="small" placeholder="選擇" filterable allow-create clearable><el-option v-for="p in otherTaskOptions.handlers" :key="p.id" :label="p.full_name" :value="p.id" /></el-select></div><div>助理:<el-select v-model="otherTasks.taipeiHarbor.assistant" size="small" placeholder="選擇" filterable allow-create clearable>
                <el-option-group v-for="group in groupedOtherTaskAssistants" :key="group.label" :label="group.label">
                    <el-option v-for="p in group.options" :key="p.id" :label="p.full_name" :value="p.id"/>
                </el-option-group>
              </el-select></div><div>司機:<el-select v-model="otherTasks.taipeiHarbor.driver" size="small" placeholder="選擇" filterable allow-create clearable><el-option v-for="p in otherTaskOptions.drivers" :key="p.id" :label="p.full_name" :value="p.id" /></el-select></div></div>
              <div class="task-item-group"><div class="task-label full-width">具結</div><div>承辦人:<el-select v-model="otherTasks.affidavit.handler" size="small" placeholder="選擇" filterable allow-create clearable><el-option v-for="p in otherTaskOptions.handlers" :key="p.id" :label="p.full_name" :value="p.id" /></el-select></div><div>助理:<el-select v-model="otherTasks.affidavit.assistant" size="small" placeholder="選擇" filterable allow-create clearable>
                <el-option-group v-for="group in groupedOtherTaskAssistants" :key="group.label" :label="group.label">
                    <el-option v-for="p in group.options" :key="p.id" :label="p.full_name" :value="p.id"/>
                </el-option-group>
              </el-select></div><div>司機:<el-select v-model="otherTasks.affidavit.driver" size="small" placeholder="選擇" filterable allow-create clearable><el-option v-for="p in otherTaskOptions.drivers" :key="p.id" :label="p.full_name" :value="p.id" /></el-select></div></div>
              <div class="task-item-group vertical-group">
                <div class="task-label full-width">休假</div>
                <div class="leave-item" v-if="allOnLeaveHandlers.length > 0">承辦人: {{ allOnLeaveHandlers.join('、') }}</div>
                <div class="leave-item" v-if="allOnLeaveAssistants.length > 0">助理: {{ allOnLeaveAssistants.join('、') }}</div>
                <div class="leave-item" v-if="allOnLeaveDrivers.length > 0">司機: {{ allOnLeaveDrivers.join('、') }}</div>
                <div class="leave-item" v-if="allOnLeaveHandlers.length === 0 && allOnLeaveAssistants.length === 0 && allOnLeaveDrivers.length === 0">
                  無相關組別人員休假
                </div>
                <div class="manual-leave-selector">
                  <el-select
                    v-model="otherTasks.onLeave.manualOnLeave"
                    multiple
                    placeholder="手動新增臨時請假人員"
                    size="small"
                    clearable
                    filterable
                    style="width: 100%;"
                  >
                    <el-option-group v-for="group in manualLeaveOptions" :key="group.label" :label="group.label">
                      <el-option v-for="p in group.options" :key="p.id" :label="p.full_name" :value="p.id" />
                    </el-option-group>
                  </el-select>
                </div>
              </div>
              <div class="task-item-group">
                <div class="task-label full-width">留守人員</div>
                <div>放單人員:
                  <el-select v-model="otherTasks.otherDuties.person" multiple size="small" placeholder="選擇" filterable clearable>
                    <el-option v-for="p in otherTaskOptions.assistants" :key="p.id" :label="p.full_name" :value="p.id" />
                  </el-select>
                </div>
                <div>其他公務:
                  <el-select v-model="otherTasks.otherDuties.otherDutiesPersonnel" multiple size="small" placeholder="選擇" filterable clearable>
                    <el-option v-for="p in otherTaskOptions.assistants" :key="p.id" :label="p.full_name" :value="p.id" />
                  </el-select>
                </div>
              </div>
              <div class="task-item full-width taxi-input-container">
                <span class="task-label">計程車號:</span>
                <div class="taxi-content-wrapper">
                    <div class="tag-input-wrapper">
                        <el-tag
                          v-for="tag in otherTasks.taxiNumbers"
                          :key="tag"
                          closable
                          :disable-transitions="false"
                          @close="handleTaxiClose(tag)"
                        >
                          {{ tag }}
                        </el-tag>
                        <el-input
                          v-model="taxiInput"
                          size="small"
                          placeholder="輸入自訂車號後按 Enter"
                          @keyup.enter="handleTaxiInputConfirm"
                          class="taxi-manual-input"
                        />
                    </div>
                    <el-checkbox-group v-model="otherTasks.taxiNumbers" class="predefined-taxi-group">
                        <el-checkbox v-for="taxi in predefinedTaxis" :key="taxi" :label="taxi" border size="small"/>
                    </el-checkbox-group>
                </div>
              </div>
            </div>
          </el-card>
        </div>
      </div>
       <div class="form-footer">
        <div>臨場查驗派遣統計：</div>
        <div>承辦人：<span>{{ handlerCount }}</span> 人</div>
        <div>助理：<span>{{ assistantCount }}</span> 人</div>
        <div>計程車：<span>{{ taxiCount }}</span> 台</div>
        <div>公務車：<span>{{ officialCarCount }}</span> 台</div>
      </div>
    </div>
    
    <div class="fab-button share-image-fab no-print" @click="shareImage" title="分享表單圖片">
      <el-icon v-if="!isGeneratingImage"><Share /></el-icon>
      <el-icon v-else class="is-loading"><Loading /></el-icon>
    </div>
    <div class="fab-button generate-image-fab no-print" @click="generateImage" title="將表單另存為圖片">
      <el-icon v-if="!isGeneratingImage"><Camera /></el-icon>
      <el-icon v-else class="is-loading"><Loading /></el-icon>
    </div>
  </div>


  <div class="print-area" ref="printAreaRef">
    <div class="print-header">
      <div class="print-title">基辦臨場查驗派遣單</div>
      <div class="print-date">{{ formattedDate }}</div>
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
                <div class="task-row" v-if="allOnLeaveHandlers.length > 0"><span class="label">承辦人:</span> <span class="value">{{ allOnLeaveHandlers.join('、') }}</span></div>
                <div class="task-row" v-if="allOnLeaveAssistants.length > 0"><span class="label">助理:</span> <span class="value">{{ allOnLeaveAssistants.join('、') }}</span></div>
                <div class="task-row" v-if="allOnLeaveDrivers.length > 0"><span class="label">司機:</span> <span class="value">{{ allOnLeaveDrivers.join('、') }}</span></div>
            </div>
             <div class="task-group">
                <div class="group-title">留守人員</div>
                <div class="task-row">
                  <span class="label">放單人員:</span>
                  <span class="value">{{ (otherTasks.otherDuties.person || []).map(id => personnelMap.get(id) || id).join('、') }}</span>
                </div>
                <div class="task-row">
                  <span class="label">其他公務:</span>
                  <span class="value">{{ (otherTasks.otherDuties.otherDutiesPersonnel || []).map(id => personnelMap.get(id) || id).join('、') }}</span>
                </div>
            </div>
            <div class="task-row full-width">
              <span class="label">計程車號:</span>
              <div class="value taxi-list-container">
                <span v-for="(taxi, index) in otherTasks.taxiNumbers" :key="taxi" class="taxi-item">
                  {{ taxi }}{{ index < otherTasks.taxiNumbers.length - 1 ? '、' : '' }}
                </span>
              </div>
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
/* --- 主要佈局與容器樣式 --- */

/* 最外層的容器，定義了整個頁面的邊距和最大寬度 */
.dispatch-form-container {
  padding: 2em; /* 內邊距 */
  max-width: 1600px; /* 最大寬度，避免在超大螢幕上過度拉伸 */
  margin: 0 auto; /* 水平置中 */
}

/* 用於顯示所有可操作UI的白色背景區域 */
.form-capture-area {
  background-color: #fff;
  padding: 1.5rem;
  border: 1px solid #ddd;
  border-radius: 8px;
}

/* 頁面頂部標頭區塊，包含所有頂部控制項 */
.page-header {
  display: flex;
  justify-content: space-between; /* 項目兩端對齊 */
  align-items: center; /* 垂直置中 */
  margin-bottom: 2rem;
  flex-wrap: wrap; /* 在螢幕空間不足時允許換行 */
  gap: 1rem; /* 項目之間的間距 */
}

/* 標頭左側按鈕區容器 (返回、清除草稿) */
.header-left {
    display: flex;
    gap: 1rem;
}

/* 日期選擇器與上下午切換的容器 */
.date-selector {
  display: flex;
  align-items: center;
  flex-shrink: 1; /* 空間不足時允許此容器被壓縮 */
}

/* 顯示格式化日期的文字 */
.date-display {
  font-size: 1.2rem;
  font-weight: 500;
  color: #606266;
}

/* 總件數文字 */
.total-cases {
  font-size: 1.2rem;
  font-weight: 500;
}

/* 主內容區，使用 Flexbox 排列左右兩欄 */
.form-content {
  display: flex;
  gap: 1.5rem;
}

/* 左側主表格的容器 */
.main-table-wrapper {
  flex: 3; /* 在 Flexbox 中佔據 3 個單位寬度 */
}

/* 右側其他任務的容器 */
.other-tasks-wrapper {
  flex: 1; /* 在 Flexbox 中佔據 1 個單位寬度 */
  min-width: 400px; /* 最小寬度，防止過度壓縮 */
}


/* --- Element Plus 元件深度樣式修改 --- */
/* :deep() 用於穿透 Scoped CSS，修改 Element Plus 子元件的內部樣式 */

/* 表格整體字體大小 */
:deep(.el-table) {
  font-size: 14px;
}

/* 表格頭部背景色 */
:deep(.el-table th.el-table__cell) {
  background-color: #f5f7fa;
}

/* 表格儲存格的內邊距 */
:deep(.el-table td.el-table__cell),
:deep(.el-table th.el-table__cell) {
  padding: 6px;
}

/* [可調整] 統一設定表格內輸入框與選擇框的字體大小 */
:deep(.el-table .el-input__inner) {
    font-size: 14px;
}

/* 已在使用的選項樣式 (粗體藍色)，應用於下拉選單中 */
:deep(.el-select-dropdown__item.already-in-use) {
  color: #409EFF;
  font-weight: bold;
}


/* --- 其他元件與細節樣式 --- */

/* 拖曳排序的圖示 */
.drag-handle {
  cursor: grab; /* 鼠標樣式為可抓取 */
  font-size: 18px;
}
.drag-handle:active {
  cursor: grabbing; /* 按下時的鼠標樣式 */
}

/* 右側其他任務卡片內的網格佈局 */
.other-tasks-grid {
  display: flex;
  flex-direction: column; /* 垂直排列 */
  gap: 12px;
}

/* 右側任務項目 */
.task-item,
.task-item-group {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 8px;
  font-size: 15px;
}

/* 手動休假選擇器容器的上邊距 */
.manual-leave-selector {
    margin-top: 8px;
    width: 100%;
}

/* 任務標籤文字 (例如 "送公文司機:") */
.task-label {
  font-weight: 500;
  white-space: nowrap; /* 不換行 */
}

/* 佔滿整行的通用 class */
.full-width {
  width: 100%;
}

/* 任務群組中的子項目，使其能自動填滿空間 */
.task-item-group > div:not(.task-label) {
  flex: 1;
  min-width: 120px;
}

/* 頁面底部的統計數據區塊 */
.form-footer {
  margin-top: 1.5rem;
  padding: 1rem;
  border: 1px solid #ddd;
  font-size: 1.1rem;
  font-weight: 500;
  display: flex;
  flex-wrap: wrap; /* 自動換行 */
  gap: 1.5rem;
  background-color: #f5f7fa;
  border-radius: 4px;
}

/* 統計數據項目 */
.form-footer > div {
  display: flex;
  align-items: center;
  gap: 0.5rem;
}

/* 統計數字的樣式 */
.form-footer span {
  font-weight: bold;
  color: #409EFF;
  font-size: 1.2rem;
}

/* 懸浮按鈕 (FAB) 的通用樣式 */
.fab-button {
  position: fixed;
  right: 30px;
  width: 50px;
  height: 50px;
  color: white;
  border-radius: 50%;
  display: flex;
  justify-content: center;
  align-items: center;
  font-size: 24px;
  cursor: pointer;
  box-shadow: 0 2px 8px rgba(0,0,0,0.2);
  transition: all 0.3s ease;
  z-index: 1000;
}
.fab-button:hover {
  transform: scale(1.1);
}

/* 分享按鈕的獨立樣式 */
.share-image-fab {
  bottom: 95px; /* 位於儲存按鈕上方 */
  background-color: #409EFF; /* 主題藍色 */
}

/* 儲存按鈕的樣式 */
.generate-image-fab {
  bottom: 30px;
  background-color: #67C23A; /* 成功綠色 */
}

/* 計程車號輸入區塊的容器 */
.taxi-input-container {
  display: flex;
  align-items: flex-start; /* 標籤與內容頂部對齊 */
}

/* 包裹標籤和預設選項的容器 */
.taxi-content-wrapper {
  flex: 1;
  display: flex;
  flex-direction: column;
  gap: 10px; /* 標籤輸入區和預設選項區的間距 */
}

/* 已輸入的計程車號標籤容器 */
.tag-input-wrapper {
  display: flex;
  flex-wrap: wrap;
  align-items: center;
  gap: 5px;
}

/* 手動輸入計程車號的輸入框 */
.taxi-manual-input {
    width: 180px;
}

/* 預設計程車號勾選區的容器 */
.predefined-taxi-group {
    display: grid;
    grid-template-columns: repeat(3, 1fr); /* 預設為三欄 */
    gap: 10px;
}

/* 移除 Element Plus 帶邊框 checkbox 的預設外距，改由 gap 控制 */
.predefined-taxi-group :deep(.el-checkbox.is-bordered) {
    margin: 0;
}


/* --- 列印專用區塊的樣式 (截圖時使用) --- */
/* 這部分的樣式與響應式無關，只為了輸出乾淨的圖片 */
.print-area {
  font-family: 'Microsoft JhengHei', '微軟正黑體', sans-serif;
  position: absolute;
  left: -9999px; /* 移出畫面外，使用者不可見 */
  top: 0;
  width: 800px; /* [可調整] 輸出圖片的寬度，影響 A4 直式比例 */
  background: #fff;
  padding: 40px;
  color: #000;
  font-size: 16px; /* [可調整] 輸出圖片的基礎字體大小 */
  border: 1px solid #ccc;
}
.print-header { text-align: center; margin-bottom: 20px; position: relative; }
.print-title { font-size: 26px; font-weight: bold; } /* [可調整] 圖片標題字體大小 */
.print-date, .print-total-cases { position: absolute; bottom: 0; font-size: 16px; }
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
.task-row { display: flex; align-items: baseline; }
.task-row .label { font-weight: 500; margin-right: 8px; white-space: nowrap; }
.task-row .value { word-break: break-word; }
.taxi-list-container {
  display: grid;
  grid-template-columns: repeat(2, auto); /* 設定為兩欄，寬度自動 */
  gap: 0 1em; /* 設定欄間距，不設定行間距 */
  justify-items: start; /* 讓項目在網格單元格內靠左對齊 */
}
.taxi-item {
  white-space: nowrap;
}
.print-footer { margin-top: 15px; font-weight: 500; display: flex; gap: 20px; font-size: 16px; }


/* --- RWD 響應式設計 --- */

/* 中等螢幕斷點 (例如：直立的平板)，當寬度小於 1200px 時 */
@media (max-width: 1200px) {
  /* 主內容區的左右兩欄改為上下堆疊 */
  .form-content {
    flex-direction: column;
  }
  /* 右側面板寬度設為100%，以填滿容器 */
  .other-tasks-wrapper {
    min-width: 100%;
  }
}

/* 小型螢幕斷點 (例如：手機)，當寬度小於 768px 時 */
@media (max-width: 768px) {
  /* 縮小最外層容器的邊距 */
  .dispatch-form-container {
    padding: 1em;
  }
  /* 頂部標頭區塊改為垂直堆疊，並靠左對齊 */
  .page-header {
    flex-direction: column;
    align-items: flex-start;
  }
  /* 計程車勾選清單從三欄變為兩欄 */
  .predefined-taxi-group {
    grid-template-columns: repeat(2, 1fr);
  }
}

/* 極小型螢幕斷點 (例如：較窄的手機)，當寬度小於 480px 時 */
@media (max-width: 480px) {
    /* 計程車勾選清單從兩欄變為單欄，方便點選 */
    .predefined-taxi-group {
        grid-template-columns: 1fr;
    }
    /* 懸浮按鈕稍微縮小並靠近邊緣 */
    .fab-button {
        right: 20px;
    }
    .share-image-fab {
        bottom: 85px;
        width: 45px;
        height: 45px;
        font-size: 20px;
    }
    .generate-image-fab {
        bottom: 20px;
        width: 45px;
        height: 45px;
        font-size: 20px;
    }
}
</style>