<template>
  <div class="admin-layout">
    <aside class="sidebar">
      <h2>管理選單</h2>
      <el-menu :router="true" :default-active="$route.path">
        <el-menu-item index="/admin/users">使用者管理</el-menu-item>
        <el-menu-item index="/admin/quotas">名額設定</el-menu-item>
      </el-menu>
    </aside>
    <main class="content-area">
      <router-view />
    </main>
  </div>
</template>

<script setup>
// 這個檔案的 script 區塊可以是空的，如果沒有其他邏輯的話
</script>

<style scoped>
.admin-layout {
  display: flex;
  /* 減去 App.vue Header 的高度，讓此佈局填滿剩餘的垂直空間 */
  /* 您可以根據您 Header 的實際高度微調 55px */
  min-height: calc(100vh - 55px);
}

.sidebar {
  width: 200px;
  flex-shrink: 0; /* 關鍵：確保側邊欄寬度永遠不會被內容擠壓而縮小 */
  padding: 1em;
  border-right: 1px solid #e0e0e0;
  background-color: #ffffff; /* 建議給個背景色，以防萬一 */
}

.content-area {
  flex-grow: 1;     /* 關鍵：讓主內容區佔滿所有剩餘的空間 */
  padding: 2em;     /* 在這裡統一設定所有管理頁面的內邊距 */
  overflow-x: auto; /* 如果內容真的超出寬度（例如很寬的表格），讓內容區內部產生滾動條，而不是影響佈局 */
}
</style>