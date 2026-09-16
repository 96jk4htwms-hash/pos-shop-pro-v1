/* ==========================================
   BACKUP / RESTORE / FACTORY RESET
   ทั้งสามฟังก์ชันทำงานกับ localStorage โดยตรงแล้วสั่ง location.reload() ให้แอปโหลดสถานะใหม่
   ตั้งแต่ต้น แทนที่จะพยายามรีเซ็ตตัวแปร/หน้าจอทีละจุดเอง (แอปมีจุดเก็บ state กระจายอยู่หลายที่
   reload สะอาดกว่าและชัวร์กว่าว่าทุกอย่างจะสอดคล้องกันแน่ๆ)
   ========================================== */
(function(){
  const DB_KEY = 'pos_full_db_state';
  const LEGACY_DB_KEY = 'pos_enterprise_state'; // เก็บไว้เผื่อเครื่องเก่ายังไม่ migrate

  // ---------------- สำรองข้อมูล (BACKUP) ----------------
  window.exportFullBackup = function(){
    try {
      // Strip local-device-only secrets before export — authEmail/authPassword are the
      // synthetic Supabase Auth credentials window.provisionEmployeeAuthAccount creates for
      // background per-employee session switching. They must never leave this device (a backup
      // file gets emailed, put in cloud drives, etc.), and dropping them here is harmless: the
      // next time each employee logs in with their PIN, they're simply re-provisioned fresh.
      const sanitizedUsers = (db.users || []).map(u => {
        const { authEmail, authPassword, _authUserId, ...rest } = u;
        return rest;
      });
      const backup = {
        _backupMeta: {
          app: 'smart-pos',
          exportedAt: new Date().toISOString(),
          storeName: db.storeName || ''
        },
        data: { ...db, users: sanitizedUsers }
      };
      const json = JSON.stringify(backup);
      const blob = new Blob([json], { type: 'application/json' });
      const a = document.createElement('a');
      a.href = URL.createObjectURL(blob);
      const dateStr = new Date().toISOString().slice(0, 10);
      const safeName = (db.storeName || 'ร้านค้า').replace(/[\\/:*?"<>|]/g, '');
      a.download = `สำรองข้อมูล-${safeName}-${dateStr}.json`;
      document.body.appendChild(a); a.click(); a.remove();
      window.showToast?.('สำรองข้อมูลเรียบร้อย — เก็บไฟล์นี้ไว้นอกเครื่องด้วยนะครับ');
    } catch (e) {
      console.error('backup failed', e);
      window.showAlert?.('สำรองข้อมูลไม่สำเร็จ', String(e.message || e), true);
    }
  };

  // ---------------- กู้คืนข้อมูล (RESTORE) ----------------
  window.handleRestoreFile = function(event){
    const file = event.target.files?.[0];
    event.target.value = ''; // เคลียร์ input ทันที กันเลือกไฟล์เดิมซ้ำแล้ว onchange ไม่ยิง
    if (!file) return;

    const reader = new FileReader();
    reader.onload = function(){
      let parsed;
      try {
        parsed = JSON.parse(reader.result);
      } catch (e) {
        return window.showAlert?.('ไฟล์ไม่ถูกต้อง', 'ไฟล์นี้ไม่ใช่ไฟล์ JSON ที่อ่านได้ กรุณาเลือกไฟล์สำรองที่ได้จากปุ่ม "สำรองข้อมูลเป็นไฟล์" เท่านั้น', true);
      }

      // ตรวจแบบหลวมๆ ว่าเป็นไฟล์ backup ของแอปนี้จริง ไม่ใช่ไฟล์ JSON อะไรก็ได้ที่หลุดมาเลือกผิด
      const payload = parsed?.data && parsed?._backupMeta ? parsed.data : parsed;
      const looksValid = payload && typeof payload === 'object' &&
        ('products' in payload) && ('bills' in payload) && ('customers' in payload);
      if (!looksValid) {
        return window.showAlert?.('ไฟล์ไม่ถูกต้อง', 'ไฟล์นี้ไม่ใช่ไฟล์สำรองของระบบ POS นี้ (โครงสร้างข้อมูลไม่ตรง) กรุณาเลือกไฟล์ที่ถูกต้อง', true);
      }

      const meta = parsed?._backupMeta;
      const metaLine = meta ? `\n\nไฟล์นี้สำรองไว้เมื่อ: ${new Date(meta.exportedAt).toLocaleString('th-TH')}\nชื่อร้าน: ${meta.storeName || '-'}` : '\n\n(ไฟล์นี้ไม่มีข้อมูล metadata — อาจเป็นไฟล์เก่ามาก)';
      const sure = confirm(
        `⚠️ ยืนยันการกู้คืนข้อมูล?\n\nข้อมูลปัจจุบันทั้งหมดในเครื่องนี้จะถูกเขียนทับด้วยข้อมูลจากไฟล์นี้ทันที และ` +
        `ย้อนกลับไม่ได้ถ้าไม่มีไฟล์สำรองของข้อมูลปัจจุบันเก็บไว้ต่างหาก${metaLine}\n\nต้องการดำเนินการต่อหรือไม่?`
      );
      if (!sure) return;

      // Defensive strip, same reasoning as the export side (see exportFullBackup) — covers an
      // older backup file taken before that fix existed, or one restored onto a different
      // device than it came from, where these synthetic credentials would be meaningless anyway
      // (tied to whatever Supabase project/device originally provisioned them).
      if (Array.isArray(payload.users)) {
        payload.users = payload.users.map(u => {
          const { authEmail, authPassword, _authUserId, ...rest } = u;
          return rest;
        });
      }

      try {
        localStorage.setItem(DB_KEY, JSON.stringify(payload));
        localStorage.removeItem(LEGACY_DB_KEY); // กันโหลดผิดคีย์เก่าทับของที่เพิ่งกู้คืนมา
        window.showToast?.('กู้คืนข้อมูลสำเร็จ — กำลังโหลดแอปใหม่...');
        setTimeout(() => location.reload(), 800);
      } catch (e) {
        console.error('restore failed', e);
        window.showAlert?.('กู้คืนข้อมูลไม่สำเร็จ', 'พื้นที่จัดเก็บข้อมูลในเครื่องอาจเต็มหรือถูกบล็อก: ' + String(e.message || e), true);
      }
    };
    reader.onerror = () => window.showAlert?.('อ่านไฟล์ไม่สำเร็จ', 'ไม่สามารถอ่านไฟล์ที่เลือกได้ ลองเลือกไฟล์ใหม่อีกครั้ง', true);
    reader.readAsText(file);
  };

  // ---------------- คืนค่าโรงงาน (FACTORY RESET) ----------------
  // ค่าเริ่มต้นล้างเฉพาะข้อมูลในเครื่องนี้ (localStorage) เท่านั้น — ไม่แตะข้อมูลบน Supabase คลาวด์
  // เว้นแต่เจ้าของร้านเลือก "ล้างข้อมูลบนคลาวด์ด้วย" ในขั้นตอนถัดไป (ต้องมีการเชื่อมต่อ Supabase
  // อยู่ก่อน และต้องล็อกอินเป็นเจ้าของร้าน — ฟังก์ชัน factory_reset_cloud_data() ฝั่งเซิร์ฟเวอร์บังคับ
  // ตรวจ is_owner() ซ้ำอีกชั้นด้วย ต่อให้ฝั่งแอปเช็คพลาดไปก็ยังปลอดภัย)
  // ต้องยืนยันหลายชั้น (confirm + พิมพ์ข้อความยืนยัน) เพราะเป็นการกระทำที่ย้อนกลับไม่ได้และรุนแรงที่สุด
  // — ยิ่งรุนแรงขึ้นไปอีกถ้าเลือกล้างคลาวด์ด้วย เพราะกระทบข้อมูลที่ทุกเครื่อง/พนักงานใช้ร่วมกัน ไม่ใช่
  // แค่เครื่องนี้เครื่องเดียว
  window.factoryReset = async function(){
    const step1 = confirm(
      '☠️ คืนค่าโรงงาน — ล้างข้อมูลทั้งหมดในเครื่องนี้?\n\n' +
      'สินค้า, ลูกค้า, บิล, ผู้ใช้, การตั้งค่า และการเชื่อมต่อฐานข้อมูล Supabase ในเครื่องนี้จะถูกลบถาวร ย้อนกลับไม่ได้ถ้าไม่มีไฟล์สำรอง\n\n' +
      'แนะนำให้กด "สำรองข้อมูลเป็นไฟล์" ก่อนถ้ายังไม่ได้ทำ ต้องการดำเนินการต่อหรือไม่?'
    );
    if (!step1) return;

    // ถามแยกต่างหากว่าจะล้างข้อมูลบนคลาวด์ด้วยไหม — เสนอตัวเลือกนี้ก็ต่อเมื่อมีการเชื่อมต่อ Supabase
    // ไว้จริงเท่านั้น (ไม่งั้นไม่มีอะไรให้ล้าง คำถามจะดูสับสนเปล่าๆ)
    let wipeCloud = false;
    const client = window.getSupabaseClient?.();
    if (client) {
      wipeCloud = confirm(
        '🌐 ล้างข้อมูลบนคลาวด์ (Supabase) ของร้านนี้ด้วยหรือไม่?\n\n' +
        'ถ้าเลือก "ตกลง": สินค้า/หมวดหมู่/ลูกค้า/ซัพพลายเออร์/บิลขาย/กะ/ใบสั่งซื้อ/ประวัติสต็อก/เจ้าหนี้การค้า ' +
        'ทั้งหมดบนคลาวด์จะถูกลบถาวร — กระทบทุกเครื่อง/พนักงานที่ใช้ร้านนี้ร่วมกัน ไม่ใช่แค่เครื่องนี้ ' +
        '(บัญชีเจ้าของร้านของคุณเองจะไม่ถูกลบ ยังล็อกอินกลับเข้ามาได้ปกติ ส่วนพนักงานคนอื่นจะถูกลบทั้งหมด)\n\n' +
        'เฉพาะเจ้าของร้านเท่านั้นที่ทำรายการนี้ได้ — ถ้าล็อกอินเป็นพนักงาน/ผู้จัดการ ระบบจะปฏิเสธคำขอนี้\n\n' +
        'ถ้าเลือก "ยกเลิก": จะล้างเฉพาะข้อมูลในเครื่องนี้เท่านั้นตามปกติ ข้อมูลบนคลาวด์จะไม่ถูกกระทบ'
      );
    }

    const requiredPhrase = wipeCloud ? 'ล้างข้อมูลทั้งหมด' : 'ล้างข้อมูล';
    const confirmText = prompt(
      `เพื่อความปลอดภัย กรุณาพิมพ์คำว่า "${requiredPhrase}" (ไม่มีเว้นวรรค) แล้วกดตกลง เพื่อยืนยัน` +
      (wipeCloud ? 'การล้างข้อมูลทั้งเครื่องนี้และบนคลาวด์:' : 'การคืนค่าโรงงาน:')
    );
    if (confirmText !== requiredPhrase) {
      if (confirmText !== null) window.showAlert?.('ยกเลิกแล้ว', 'ข้อความยืนยันไม่ตรง จึงไม่ได้ล้างข้อมูลใดๆ', true);
      return;
    }

    if (wipeCloud) {
      // ล้างคลาวด์ก่อนเสมอ ขณะที่ client/session ของเครื่องนี้ยังเรียกใช้ได้อยู่ (ยังไม่ได้ signOut/
      // ล้าง url-key ด้านล่าง) ถ้าขั้นนี้พลาด (ไม่ใช่เจ้าของร้าน, ออฟไลน์, ฯลฯ) ให้หยุดทั้งหมดทันที —
      // ไม่ทำการล้างเครื่องนี้ต่อแบบเงียบๆ เพราะเจ้าของร้านตั้งใจจะล้างทั้งคู่ ไม่ใช่แค่เครื่องเดียว
      try {
        const { error } = await client.rpc('factory_reset_cloud_data');
        if (error) throw error;
      } catch (e) {
        console.error('cloud factory reset failed', e);
        window.showAlert?.(
          'ล้างข้อมูลบนคลาวด์ไม่สำเร็จ',
          'ยกเลิกการคืนค่าโรงงานทั้งหมด (ทั้งเครื่องนี้และคลาวด์) เพื่อไม่ให้ข้อมูลค้างอยู่ครึ่งๆ กลางๆ — ' +
          'สาเหตุที่พบ: ' + String(e.message || e) + '\n\nลองตรวจสอบว่าล็อกอินเป็น "เจ้าของร้าน" และมีการเชื่อมต่ออินเทอร์เน็ตอยู่ แล้วลองใหม่อีกครั้ง',
          true
        );
        return;
      }
    }

    try {
      // Sign out of Supabase Auth FIRST, while the client can still be built (needs url/key,
      // which are about to be wiped below) — this properly revokes the session server-side too,
      // not just locally. Best-effort: if it's not configured or offline, there's nothing to
      // sign out of, and the key removal below still leaves this device fully disconnected.
      try {
        if (client) await client.auth.signOut();
      } catch (e) {
        console.warn('factory reset: supabase signOut failed (continuing anyway)', e);
      }

      // ลบเฉพาะคีย์ของแอปนี้ ไม่แตะ localStorage ของเว็บไซต์อื่นที่อาจแชร์โดเมนเดียวกัน (ไม่มีในเคสนี้ แต่กันไว้)
      // รวมถึงการตั้งค่าเชื่อมต่อ Supabase ด้วย เพราะถ้าจะส่งต่อเครื่องให้ร้านอื่นแล้วยังต่อฐานข้อมูล
      // เดิมค้างอยู่ ร้านใหม่จะดันไปดึง/ส่งข้อมูลชนกับร้านเก่าทันทีที่เปิดแอป — pos_debug_mode ต้อง
      // ล้างด้วยเหตุผลเดียวกัน: กันไม่ให้ร้านใหม่เปิดมาเจอกล่อง debug ค้างเปิดอยู่โดยไม่ได้ตั้งใจ
      [DB_KEY, LEGACY_DB_KEY, 'pos_products_grid_cols', 'pos_products_per_page', 'pos_supabase_url', 'pos_supabase_anon_key', 'pos_debug_mode'].forEach(k => localStorage.removeItem(k));
      window.showToast?.(wipeCloud ? 'ล้างข้อมูลทั้งเครื่องนี้และบนคลาวด์เรียบร้อย — กำลังเริ่มต้นใหม่...' : 'ล้างข้อมูลเรียบร้อย — กำลังเริ่มต้นใหม่...');
      setTimeout(() => location.reload(), 600);
    } catch (e) {
      console.error('factory reset failed', e);
      window.showAlert?.('ล้างข้อมูลไม่สำเร็จ', String(e.message || e), true);
    }
  };
})();
