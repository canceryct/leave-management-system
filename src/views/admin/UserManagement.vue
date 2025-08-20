<script setup>
// --- 這整個 <script setup> 區塊的內容保持不變 ---
import { ref, reactive, onMounted, onUnmounted } from 'vue';
import { supabase } from '../../supabase';
import { ElMessage, ElNotification, ElMessageBox } from 'element-plus';

const users = ref([]);
const groups = ref([]);
const loading = ref(true);
const dialogVisible = ref(false);
const isEditMode = ref(false);
const formRef = ref(null);
const form = reactive({ id: null, username: '', full_name: '', email: '', password: '', group_id: null, role: 'user' });
const rules = reactive({
  username: [{ required: true, message: '請輸入使用者帳號', trigger: 'blur' }],
  email: [{ required: true, message: '請輸入 Email', trigger: 'blur' }, { type: 'email', message: '請輸入有效的 Email 格式', trigger: ['blur', 'change'] }],
  password: [{ required: true, message: '請輸入初始密碼', trigger: 'blur' }, { min: 6, message: '密碼長度至少需要 6 個字元', trigger: 'blur' }],
});
const resetForm = () => { Object.assign(form, { id: null, username: '', full_name: '', email: '', password: '', group_id: null, role: 'user' }); };
const resetFormAndValidation = () => { resetForm(); formRef.value?.clearValidate(); };
async function fetchUsers() {
  const { data, error } = await supabase.rpc('get_user_management_list');
  if (error) { ElMessage.error('讀取使用者列表失敗: ' + error.message); } 
  else {
    users.value = data.map(u => ({
      id: u.id, username: u.username, full_name: u.full_name, email: u.email, role: u.role,
      groups: { id: u.group_id, name: u.group_name }
    }));
  }
}
async function fetchGroups() {
  const { data, error } = await supabase.from('groups').select('*');
  if (error) { ElMessage.error('讀取組別列表失敗: ' + error.message); } else { groups.value = data; }
}
const openCreateDialog = () => { resetForm(); isEditMode.value = false; dialogVisible.value = true; };
const openEditDialog = (user) => {
  resetForm(); isEditMode.value = true;
  Object.assign(form, {
    id: user.id, username: user.username, full_name: user.full_name,
    email: user.email, group_id: user.groups?.id, role: user.role,
  });
  dialogVisible.value = true;
};
async function handleSubmit() {
  if (!formRef.value) return;
  await formRef.value.validate(async (valid) => {
    if (valid) {
      try {
        if (isEditMode.value) {
          const { error } = await supabase.functions.invoke('update-user', { body: form });
          if (error) throw error;
          ElNotification.success('使用者更新成功！');
        } else {
          const { error } = await supabase.functions.invoke('create-user', { body: form });
          if (error) throw error;
          ElNotification.success('新使用者已成功建立！');
        }
        dialogVisible.value = false;
        await fetchUsers();
      } catch (error) { ElMessage.error(`${isEditMode.value ? '更新' : '建立'}失敗：${error.message}`); }
    } else { ElMessage.error('表單驗證失敗，請檢查輸入！'); }
  });
}
async function handleDelete(user) {
  try {
    await ElMessageBox.confirm(`確定要刪除使用者 ${user.full_name || user.username} 嗎？此操作無法復原。`, '警告', { type: 'warning' });
    const { error } = await supabase.functions.invoke('delete-user', { body: { id: user.id } });
    if (error) throw error;
    ElNotification.success('使用者刪除成功！');
    await fetchUsers();
  } catch (error) {
    if (error !== 'cancel' && error.message !== 'Operation cancelled') { ElMessage.error('刪除失敗：' + error.message); }
  }
}
async function handleGenerateResetLink(user) {
  try {
    const { data, error } = await supabase.functions.invoke('generate-password-reset', {
      body: { email: user.email, site_url: window.location.origin }
    });
    if (error) throw error;
    await ElMessageBox.alert(
      `請複製以下連結並傳送給使用者 <strong>${user.full_name || user.username}</strong>：<br/><br/>
       <input type="text" value="${data.resetLink}" style="width: 100%; padding: 8px; border: 1px solid #ccc; border-radius: 4px;" readonly onclick="this.select()">`,
      '密碼重設連結',
      { dangerouslyUseHTMLString: true, confirmButtonText: '我已複製' }
    );
  } catch (error) { ElMessage.error('產生連結失敗: ' + error.message); }
}
const handleVisibilityChange = () => { if (!document.hidden) { location.reload(); } };
onMounted(async () => {
  loading.value = true;
  await Promise.all([fetchUsers(), fetchGroups()]);
  loading.value = false;
  document.addEventListener('visibilitychange', handleVisibilityChange);
});
onUnmounted(() => {
  document.removeEventListener('visibilitychange', handleVisibilityChange);
});
</script>

<template>
    <div style="padding: 2em;">
    <div style="display: flex; justify-content: space-between; align-items: center;">
      <h1>使用者管理</h1>
      <el-button type="primary" @click="openCreateDialog">新增使用者</el-button>
    </div>
    <p>在這裡，您可以新增、編輯、刪除使用者，並為他們分配組別與重設密碼。</p>
    <el-table :data="users" v-loading="loading" border stripe style="width: 100%; margin-top: 20px;">
      <el-table-column prop="username" label="使用者帳號" width="150" />
      <el-table-column prop="full_name" label="姓名" width="80" />
      <el-table-column prop="email" label="Email" min-width="220" /> 
      <el-table-column prop="role" label="角色" width="80" />
      <el-table-column label="所屬組別" width="150">
         <template #default="scope">{{ scope.row.groups?.name || '未分配' }}</template>
      </el-table-column>
      <el-table-column label="操作" width="220" fixed="right">
        <template #default="scope">
          <div>
            <el-button size="small" @click="openEditDialog(scope.row)">編輯</el-button>
            <el-button size="small" type="warning" @click="handleGenerateResetLink(scope.row)">重設密碼</el-button>
            <el-button size="small" type="danger" @click="handleDelete(scope.row)">刪除</el-button>
          </div>
        </template>
      </el-table-column>
    </el-table>

    <el-dialog v-model="dialogVisible" :title="isEditMode ? '編輯使用者' : '新增使用者'" width="500px" @close="resetFormAndValidation">
      <el-form :model="form" :rules="rules" ref="formRef" label-width="120px">
        <el-form-item label="使用者帳號" prop="username" for="username-input">
          <el-input v-model="form.username" :disabled="isEditMode" id="username-input" />
        </el-form-item>
        <el-form-item label="姓名" prop="full_name" for="fullname-input">
          <el-input v-model="form.full_name" id="fullname-input" />
        </el-form-item>
        <el-form-item label="Email" prop="email" for="email-input">
          <el-input v-model="form.email" id="email-input" />
        </el-form-item>
        <el-form-item v-if="!isEditMode" label="初始密碼" prop="password" for="password-input">
          <el-input v-model="form.password" type="password" show-password id="password-input" />
        </el-form-item>
        <el-form-item label="所屬組別" prop="group_id" for="group-select">
          <el-select v-model="form.group_id" placeholder="請選擇組別" style="width: 100%;" id="group-select">
            <el-option v-for="group in groups" :key="group.id" :label="group.name" :value="group.id" />
          </el-select>
        </el-form-item>
        <el-form-item label="角色" prop="role" for="role-radiogroup">
           <el-radio-group v-model="form.role" id="role-radiogroup">
            <el-radio label="user">一般使用者</el-radio>
            <el-radio label="admin">管理員</el-radio>
          </el-radio-group>
        </el-form-item>
      </el-form>
      <template #footer>
        <span class="dialog-footer">
          <el-button @click="dialogVisible = false">取消</el-button>
          <el-button type="primary" @click="handleSubmit">確定</el-button>
        </span>
      </template>
    </el-dialog>
  </div>
</template>

<style scoped>
/* 新增統一的頁面容器樣式 */
.page-container {
  /* 讓容器嘗試佔滿父元素的可用寬度 */
  width: 100%; 
  /* 限制最大寬度，在大螢幕上不會過寬 */
  padding: 2em;
  /* 確保 padding 不會撐大容器的總寬度 */
  box-sizing: border-box; 
}
.table-container {
  width: 100%;
  overflow-x: auto; /* 關鍵：當內容超出寬度時，允許橫向滾動 */
}
</style>