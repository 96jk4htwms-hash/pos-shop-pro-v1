/* ==========================================
   FIRST-LAUNCH SETUP WIZARD (IMPROVED)
   ========================================== */
(function(){
  const STEP_IDS = [
    'wizard-step-welcome',
    'wizard-step-cloud',
    'wizard-step-which-device',
    'wizard-step-guide-first',
    'wizard-step-guide-additional',
    'wizard-step-finish'
  ];

  function showStep(id){
    STEP_IDS.forEach(s => {
      const el = document.getElementById(s);
      if (el) el.classList.toggle('hidden', s !== id);
    });
  }

  window.maybeShowSetupWizard = function(){
    try {
      window.ensure?.(); // แน่ใจว่า db.users และ db.storeName พร้อมทำงาน
      if (db.setupWizardDone) return;

      // ล้างช่องกรอก PIN เพื่อความปลอดภัยและความสดใหม่ของฟอร์ม
      const storeInput = document.getElementById('wizard-store-name');
      const pinInput = document.getElementById('wizard-owner-pin');
      const pin2Input = document.getElementById('wizard-owner-pin2');

      if (storeInput) storeInput.value = db.storeName || '';
      if (pinInput) pinInput.value = '';
      if (pin2Input) pin2Input.value = '';

      showStep('wizard-step-welcome');
      const modal = document.getElementById('modal-setup-wizard');
      if (modal) {
        modal.classList.remove('hidden');
        modal.classList.add('flex');
      }
    } catch (err) {
      console.error('Error initiating setup wizard:', err);
    }
  };

  window.wizardSaveWelcome = async function(btnElement){
    const nameInput = document.getElementById('wizard-store-name');
    const pinInput = document.getElementById('wizard-owner-pin');
    const pin2Input = document.getElementById('wizard-owner-pin2');

    const name = nameInput?.value.trim() || '';
    const pin = pinInput?.value.trim() || '';
    const pin2 = pin2Input?.value.trim() || '';

    // Validation
    if (!name) return window.showAlert?.('ข้อมูลไม่ครบ', 'กรุณากรอกชื่อร้าน', true);
    if (!/^\d{4}$/.test(pin)) return window.showAlert?.('ข้อมูลไม่ถูกต้อง', 'PIN ต้องเป็นตัวเลข 4 หลัก', true);
    if (pin !== pin2) return window.showAlert?.('PIN ไม่ตรงกัน', 'กรุณากรอก PIN ทั้งสองช่องให้ตรงกัน', true);

    // Lock UI เพื่อป้องกันการกดซ้ำระหว่างรอนาน
    if (btnElement) btnElement.disabled = true;

    try {
      db.storeName = name;
      window.ensure?.();

      // Ensure db.users Array exists
      if (!Array.isArray(db.users)) db.users = [];

      // ค้นหา Owner หากไม่มีให้ fallback สร้างใหม่ขึ้นมา
      let owner = db.users.find(u => u.role === 'OWNER');
      if (!owner) {
        owner = {
          id: typeof window.crypto?.randomUUID === 'function' ? window.crypto.randomUUID() : 'owner_' + Date.now(),
          role: 'OWNER'
        };
        db.users.push(owner);
      }

      // อัปเดตชื่อ Owner ให้สอดคล้องกับชื่อร้านเสมอ
      owner.name = name;

      // Hash PIN ด้วย UUID ของ Owner
      if (typeof window.hashPin === 'function') {
        const ownerId = owner.id || toUUID?.(owner.id) || owner.id;
        owner.pinHash = await window.hashPin(pin, ownerId);
      } else {
        throw new Error('ไม่พบฟังก์ชันสำหรับ Hash PIN');
      }

      // ล้าง plain PIN เก่าถ้ามี
      delete owner.pin;

      // บันทึกและรีเรนเดอร์หน้า UI
      window.persist?.();
      window.renderEmployeeLoginScreen?.();

      // Clear Sensitive Inputs
      if (pinInput) pinInput.value = '';
      if (pin2Input) pin2Input.value = '';

      showStep('wizard-step-cloud');

    } catch (err) {
      console.error('Failed to save welcome step:', err);
      window.showAlert?.('เกิดข้อผิดพลาด', err.message || 'ไม่สามารถบันทึกข้อมูลได้ กรุณาลองใหม่อีกครั้ง', true);
    } finally {
      if (btnElement) btnElement.disabled = false;
    }
  };

  window.wizardGoCloudSetup = function(){ showStep('wizard-step-which-device'); };

  window.wizardShowGuide = function(kind){
    showStep(kind === 'first' ? 'wizard-step-guide-first' : 'wizard-step-guide-additional');
  };

  window.wizardGoToSettings = function(){
    window.wizardFinish(false); // ปิด wizard
    window.openMasterSettingsModal?.('DATABASE');
  };

  window.wizardFinish = function(showDone){
    try {
      if (showDone !== false) showStep('wizard-step-finish');
      db.setupWizardDone = true;
      window.persist?.();

      if (showDone === false) {
        const modal = document.getElementById('modal-setup-wizard');
        if (modal) {
          modal.classList.add('hidden');
          modal.classList.remove('flex');
        }
      }
    } catch (err) {
      console.error('Error completing setup wizard:', err);
    }
  };

  window.reopenSetupWizard = function(){
    db.setupWizardDone = false;
    window.maybeShowSetupWizard();
  };

  // หน่วงเล็กน้อยให้สคริปต์หลักและ DOM โหลดเสร็จสมบูรณ์ก่อนเรียกใช้
  document.addEventListener('DOMContentLoaded', () => {
    setTimeout(() => {
      window.maybeShowSetupWizard();
    }, 300);
  });
})();
