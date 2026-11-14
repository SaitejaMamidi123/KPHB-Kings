import { LightningElement } from 'lwc';
import getDashboard from '@salesforce/apex/KPHBRoomExpensesController.getDashboard';
import addExpense from '@salesforce/apex/KPHBRoomExpensesController.addExpense';
import updateExpense from '@salesforce/apex/KPHBRoomExpensesController.updateExpense';
import deleteExpenseRecord from '@salesforce/apex/KPHBRoomExpensesController.deleteExpense';
import saveAdminSettings from '@salesforce/apex/KPHBRoomExpensesController.saveAdminSettings';
import sendMonthlyReport from '@salesforce/apex/KPHBRoomExpensesController.sendMonthlyReport';
import getAdminExpenses from '@salesforce/apex/KPHBRoomExpensesController.getAdminExpenses';
import LightningConfirm from 'lightning/confirm';
import Toast from 'lightning/toast';
import USER_ID from '@salesforce/user/Id';
import QR_LIBRARY from '@salesforce/resourceUrl/qrcodegenerator';
import { loadScript } from 'lightning/platformResourceLoader';

const LABELS = ['Veg', 'Shop', 'Utilities', 'Meat', 'Others'];
const COLORS = ['#18a999', '#6d5ce8', '#f4a340', '#e66b76', '#3b82c4'];
const CURRENCY = new Intl.NumberFormat(undefined, { style: 'currency', currency: 'INR' });

export default class KphbRoomExpenses extends LightningElement {
    data;
    isLoading = true;
    isSaving = false;
    errorMessage = '';
    showExpenseModal = false;
    showPayModal = false;
    qrDataUrl = '';
    qrError = '';
    payAmountLabel = '';
    qrLibraryLoaded = false;
    qrFile;
    rentInput = 23200;
    upiInput = '';
    showUpiId = false;
    selectedMonth = '';
    reportMonth = '';
    monthOptions = [];
    adminSaveMessage = '';
    adminExpenseRows = [];
    adminExpenseMonth = '';
    adminExpenseMember = 'all';
    adminExpenseLabel = 'all';
    isLoadingAdminExpenses = false;
    adminExpenseError = '';
    reportMessage = '';
    isSendingReport = false;
    newExpense = { label: '', name: '', amount: '' };
    editingExpenseId;
    refreshTimer;
    refreshRequestId = 0;
    adminExpenseRequestId = 0;
    observedMonthKey = '';
    boundHandleWindowFocus;
    boundHandleVisibilityChange;

    connectedCallback() {
        this.observedMonthKey = this.currentMonthKey();
        this.refresh();
        this.boundHandleWindowFocus = this.handleWindowFocus.bind(this);
        this.boundHandleVisibilityChange = this.handleVisibilityChange.bind(this);
        window.addEventListener('focus', this.boundHandleWindowFocus);
        document.addEventListener('visibilitychange', this.boundHandleVisibilityChange);
        this.refreshTimer = window.setInterval(() => {
            if (!document.hidden) this.refreshCurrentView();
        }, 30000);
    }

    disconnectedCallback() {
        window.clearInterval(this.refreshTimer);
        window.removeEventListener('focus', this.boundHandleWindowFocus);
        document.removeEventListener('visibilitychange', this.boundHandleVisibilityChange);
    }

    handleWindowFocus() {
        this.refreshCurrentView();
    }

    handleVisibilityChange() {
        if (!document.hidden) this.refreshCurrentView();
    }

    currentMonthKey() {
        const now = new Date();
        return `${now.getFullYear()}-${String(now.getMonth() + 1).padStart(2, '0')}`;
    }

    refreshCurrentView() {
        const currentMonth = this.currentMonthKey();
        if (currentMonth !== this.observedMonthKey) {
            this.observedMonthKey = currentMonth;
            this.selectedMonth = currentMonth;
            this.refresh(currentMonth);
            return;
        }
        this.refresh(this.selectedMonth, true);
    }

    async refresh(monthKey = this.selectedMonth, silent = false) {
        const requestId = ++this.refreshRequestId;
        if (!silent) this.isLoading = true;
        this.errorMessage = '';
        try {
            const result = await getDashboard({ monthKey: monthKey || '' });
            if (requestId !== this.refreshRequestId) return;
            this.data = result;
            this.selectedMonth = result.selectedMonthKey;
            if (!this.adminExpenseMonth) this.adminExpenseMonth = result.selectedMonthKey;
            if (this.adminExpenseMonth === result.selectedMonthKey) {
                this.adminExpenseRows = result.adminExpenses || [];
            } else if (result.isAdmin) {
                await this.loadAdminExpenses(this.adminExpenseMonth);
            }
            if (!this.reportMonth) this.reportMonth = result.selectedMonthKey;
            this.monthOptions = result.monthOptions || [];
            this.rentInput = result.rentAmount ?? 23200;
            this.upiInput = result.payeeUpiId || '';
        } catch (error) {
            if (requestId === this.refreshRequestId) this.errorMessage = this.getError(error);
        } finally {
            if (requestId === this.refreshRequestId) this.isLoading = false;
        }
    }

    get isAdmin() { return Boolean(this.data?.isAdmin); }
    get currentMemberInSplit() { return Boolean(this.data?.currentMemberInSplit); }
    get memberCount() { return this.data?.memberCount || 0; }
    get hasMembers() { return this.memberCount > 0; }
    get hasSettlementMembers() { return (this.data?.personTotals || []).length > 0; }
    get hasSheetMembers() { return (this.data?.members || []).length > 0; }
    get rentMemberCount() { return this.data?.rentMemberCount || 0; }
    get hasMyExpenses() { return (this.data?.myExpenses || []).length > 0; }
    get hasAdminMembers() { return (this.data?.members || []).length > 0; }
    get hasAdminExpenses() { return this.adminExpenses.length > 0; }
    get hasAdminExpenseError() { return Boolean(this.adminExpenseError); }
    get expenseModalTitle() { return this.editingExpenseId ? 'Edit expense' : 'Add an expense'; }
    get reportMonthLabel() {
        const selected = this.monthOptions.find((option) => option.value === this.reportMonth);
        if (selected) return selected.label;
        const [year, month] = (this.reportMonth || this.currentMonthKey()).split('-').map(Number);
        return new Date(year, month - 1, 1).toLocaleDateString(undefined, { month: 'long', year: 'numeric' });
    }
    get reportButtonLabel() {
        return this.isSendingReport ? 'Sending...' : 'Send report';
    }
    get myExpenses() {
        return (this.data?.myExpenses || []).map((row) => ({
            ...row,
            initial: row.name ? row.name.slice(0, 1).toUpperCase() : '•',
            amountFormatted: this.money(row.amount),
            dateLabel: row.createdDate ? new Date(row.createdDate).toLocaleString() : ''
        }));
    }
    get personTotals() {
        return (this.data?.personTotals || []).map((row) => ({
            ...row,
            spentFormatted: this.money(row.spent),
            fairShareFormatted: this.money(row.fairShare),
            getsBackFormatted: this.money(row.getsBack),
            paysExpensesFormatted: this.money(row.paysExpenses),
            expenseBalanceFormatted: this.money(row.expenseBalance),
            rentShareFormatted: this.money(row.rentShare),
            finalToPayFormatted: this.money(row.finalToPay),
            finalToPayCssClass: Number(row.finalToPay || 0) < 0
                ? 'numeric final-column final-gets-back'
                : 'numeric final-column final-owes',
            estimatedContributionFormatted: this.money(Number(row.rentShare || 0) + Number(row.fairShare || 0)),
            canPay: Boolean(this.data?.payeeUpiId) && this.isCurrentUser(row.userId) && Number(row.finalToPay || 0) > 0
        }));
    }
    isCurrentUser(userId) {
        return Boolean(userId) && String(userId).slice(0, 15) === String(USER_ID).slice(0, 15);
    }
    async handlePayAmount() {
        const me = (this.data?.personTotals || []).find((row) => this.isCurrentUser(row.userId));
        const amount = Number(me?.finalToPay || 0);
        const payeeUpiId = this.data?.payeeUpiId;
        if (amount <= 0 || !payeeUpiId) return;
        this.payAmountLabel = this.money(amount);
        this.qrError = '';
        this.qrDataUrl = '';
        this.qrFile = undefined;
        this.showPayModal = true;
        try {
            if (!this.qrLibraryLoaded) {
                await loadScript(this, QR_LIBRARY);
                this.qrLibraryLoaded = true;
            }
            const payload = `upi://pay?pa=${encodeURIComponent(payeeUpiId)}&pn=${encodeURIComponent('KPHB KINGS')}&am=${amount.toFixed(2)}&cu=INR`;
            const qr = window.qrcode(0, 'M');
            qr.addData(payload);
            qr.make();
            this.qrDataUrl = qr.createDataURL(8, 16);
            this.qrFile = await this.buildQrFile(qr, amount);
        } catch (error) {
            if (!this.qrDataUrl) this.qrError = 'Could not create the QR code. Use "Open PhonePe" and pay the UPI ID manually.';
        }
    }
    get saveQrDisabled() { return !this.qrFile; }
    buildQrFile(qr, amount) {
        const cell = 10;
        const margin = 4;
        const count = qr.getModuleCount();
        const size = (count + margin * 2) * cell;
        const canvas = document.createElement('canvas');
        canvas.width = size;
        canvas.height = size;
        const context = canvas.getContext('2d');
        context.fillStyle = '#ffffff';
        context.fillRect(0, 0, size, size);
        context.fillStyle = '#000000';
        for (let row = 0; row < count; row += 1) {
            for (let col = 0; col < count; col += 1) {
                if (qr.isDark(row, col)) context.fillRect((col + margin) * cell, (row + margin) * cell, cell, cell);
            }
        }
        return new Promise((resolve) => {
            canvas.toBlob((blob) => {
                resolve(blob ? new File([blob], `KPHB-pay-${amount.toFixed(2)}.png`, { type: 'image/png' }) : undefined);
            }, 'image/png');
        });
    }
    async handleSaveQr() {
        const file = this.qrFile;
        if (!file) return;
        try {
            if (navigator.canShare && navigator.canShare({ files: [file] })) {
                await navigator.share({ files: [file], title: 'KPHB payment QR' });
                return;
            }
            const url = URL.createObjectURL(file);
            const link = document.createElement('a');
            link.href = url;
            link.download = file.name;
            document.body.appendChild(link);
            link.click();
            document.body.removeChild(link);
            window.setTimeout(() => URL.revokeObjectURL(url), 10000);
            this.toast('QR saved', 'The QR image was saved to your downloads. Open PhonePe, tap Scan and pick it from the gallery.', 'success');
        } catch (error) {
            if (error?.name !== 'AbortError') {
                this.toast('Could not save QR', 'Take a screenshot of the QR instead.', 'error');
            }
        }
    }
    closePayModal() { this.showPayModal = false; }
    handleOpenPhonePe() {
        const payeeUpiId = this.data?.payeeUpiId;
        if (!payeeUpiId) return;
        if (navigator.clipboard?.writeText) navigator.clipboard.writeText(payeeUpiId).catch(() => {});
        this.toast('UPI ID copied', `Paste ${payeeUpiId} in PhonePe under "To UPI ID" and enter ${this.payAmountLabel}.`, 'info');
        window.location.href = 'phonepe://';
    }
    get adminMembers() {
        return (this.data?.members || []).map((member) => ({
            ...member,
            initial: member.name ? member.name.slice(0, 1).toUpperCase() : '?'
        }));
    }
    get adminExpenses() {
        return this.adminExpenseRows
            .filter((row) => this.adminExpenseMember === 'all' || row.spenderId === this.adminExpenseMember)
            .filter((row) => this.adminExpenseLabel === 'all' || row.label === this.adminExpenseLabel)
            .map((row) => ({
                ...row,
                amountFormatted: this.money(row.amount),
                dateLabel: row.createdDate ? new Date(row.createdDate).toLocaleString() : ''
            }));
    }
    get adminExpenseMemberOptions() {
        const roommateOptions = new Map();
        (this.data?.members || []).forEach((member) => {
            if (member.userId) roommateOptions.set(member.userId, { label: member.name, value: member.userId });
        });
        return [
            { label: 'All roommates', value: 'all' },
            ...[...roommateOptions.values()].sort((a, b) => a.label.localeCompare(b.label))
        ];
    }
    get adminExpenseLabelOptions() {
        return [{ label: 'All labels', value: 'all' }, ...LABELS.map((label) => ({ label, value: label }))];
    }
    get labelOptions() { return LABELS.map((label) => ({ label, value: label })); }
    get myTotal() { return (this.data?.myLabelTotals || []).reduce((sum, item) => sum + Number(item.amount || 0), 0); }
    get groupTotal() { return Number(this.data?.totalExpense || 0); }
    get myTotalFormatted() { return this.money(this.myTotal); }
    get groupTotalFormatted() { return this.money(this.groupTotal); }
    get rentFormatted() { return this.money(this.data?.rentAmount || 0); }
    get expenseShareFormatted() { return this.money(this.data?.fairShare || 0); }
    get rentShareFormatted() { return this.money(this.data?.rentShare || 0); }
    get estimatedContributionFormatted() {
        return this.money(Number(this.data?.fairShare || 0) + Number(this.data?.rentShare || 0));
    }
    get myChartItems() { return this.decorateChartItems(this.data?.myLabelTotals || []); }
    get groupChartItems() { return this.decorateChartItems(this.data?.labelTotals || []); }
    get myPieStyle() { return this.pieStyle(this.data?.myLabelTotals || []); }
    get groupPieStyle() { return this.pieStyle(this.data?.labelTotals || []); }

    get sheetMembers() {
        return [...(this.data?.members || [])]
            .sort((a, b) => a.name.localeCompare(b.name));
    }
    get sheetRows() {
        const members = this.sheetMembers;
        const grouped = new Map(members.map((member) => [member.userId || member.id, []]));
        (this.data?.selectedExpenses || []).forEach((expense) => {
            const list = grouped.get(expense.spenderId);
            if (list) list.push(expense);
        });
        const maxRows = Math.max(0, ...Array.from(grouped.values(), (list) => list.length));
        const rows = [];
        for (let index = 0; index < maxRows; index += 1) {
            rows.push({
                key: `row-${index}`,
                cells: members.map((member) => {
                    const expense = grouped.get(member.userId || member.id)[index];
                    return { key: `${member.id}-${index}`, value: expense ? `${expense.name} · ${this.money(expense.amount)}` : '' };
                })
            });
        }
        return rows;
    }
    get sheetTotals() {
        return this.sheetMembers.map((member) => {
            const total = (this.data?.selectedExpenses || [])
                .filter((expense) => expense.spenderId === member.userId)
                .reduce((sum, expense) => sum + Number(expense.amount || 0), 0);
            return { key: member.id, amount: total, amountFormatted: this.money(total) };
        });
    }
    get sheetTotalFormatted() {
        const total = this.sheetTotals.reduce((sum, item) => sum + item.amount, 0);
        return this.money(total);
    }

    decorateChartItems(totals) {
        return LABELS.map((label, index) => {
            const found = totals.find((item) => item.label === label);
            return { label, amountFormatted: this.money(found?.amount || 0), dotStyle: `background:${COLORS[index]}` };
        });
    }
    pieStyle(totals) {
        const values = LABELS.map((label) => Number(totals.find((item) => item.label === label)?.amount || 0));
        const sum = values.reduce((total, amount) => total + amount, 0);
        if (!sum) return 'background: conic-gradient(#e7ebf0 0 100%)';
        let cursor = 0;
        const segments = values.map((amount, index) => {
            const start = cursor;
            cursor += amount / sum * 100;
            return `${COLORS[index]} ${start}% ${cursor}%`;
        });
        return `background: conic-gradient(${segments.join(', ')})`;
    }
    money(value) { return CURRENCY.format(Number(value || 0)); }
    getError(error) { return error?.body?.message || error?.message || 'Something went wrong. Please try again.'; }

    openExpenseModal() {
        this.editingExpenseId = undefined;
        this.newExpense = { label: '', name: '', amount: '' };
        this.showExpenseModal = true;
    }
    closeExpenseModal() {
        this.showExpenseModal = false;
        this.editingExpenseId = undefined;
    }
    handleEditExpense(event) {
        const expenseId = event.currentTarget.dataset.id;
        const expense = [...(this.data?.myExpenses || []), ...this.adminExpenseRows]
            .find((row) => row.id === expenseId);
        if (!expense) return;
        this.editingExpenseId = expense.id;
        this.newExpense = { label: expense.label, name: expense.name, amount: String(expense.amount) };
        this.showExpenseModal = true;
    }
    handleExpenseLabelChange(event) { this.newExpense = { ...this.newExpense, label: event.detail.value }; }
    handleExpenseNameChange(event) { this.newExpense = { ...this.newExpense, name: event.target.value }; }
    handleExpenseAmountChange(event) { this.newExpense = { ...this.newExpense, amount: event.target.value }; }
    handleRentChange(event) { this.rentInput = event.target.value; }
    handleUpiChange(event) { this.upiInput = event.target.value; }
    handleToggleUpiVisibility() { this.showUpiId = !this.showUpiId; }
    get upiInputType() { return this.showUpiId ? 'text' : 'password'; }
    get upiToggleIcon() { return this.showUpiId ? 'utility:hide' : 'utility:preview'; }
    get upiToggleLabel() { return this.showUpiId ? 'Hide UPI ID' : 'Show UPI ID'; }
    handleRefresh() { this.refresh(this.selectedMonth); }
    handleMonthChange(event) {
        this.adminExpenseMonth = event.detail.value;
        this.refresh(event.detail.value);
    }
    handleAdminExpenseMemberChange(event) { this.adminExpenseMember = event.detail.value; }
    handleAdminExpenseLabelChange(event) { this.adminExpenseLabel = event.detail.value; }
    async handleAdminExpenseMonthChange(event) {
        this.adminExpenseMonth = event.detail.value;
        await this.loadAdminExpenses(this.adminExpenseMonth);
    }
    async loadAdminExpenses(monthKey) {
        const requestId = ++this.adminExpenseRequestId;
        this.isLoadingAdminExpenses = true;
        this.adminExpenseError = '';
        this.adminExpenseRows = [];
        try {
            const rows = await getAdminExpenses({ monthKey });
            if (requestId === this.adminExpenseRequestId) this.adminExpenseRows = rows;
        } catch (error) {
            if (requestId === this.adminExpenseRequestId) this.adminExpenseError = this.getError(error);
        } finally {
            if (requestId === this.adminExpenseRequestId) this.isLoadingAdminExpenses = false;
        }
    }
    async handleResetAdminExpenseFilters() {
        this.adminExpenseMember = 'all';
        this.adminExpenseLabel = 'all';
        this.adminExpenseMonth = this.selectedMonth;
        await this.loadAdminExpenses(this.adminExpenseMonth);
    }
    handleReportMonthChange(event) { this.reportMonth = event.detail.value; }
    handleMemberToggle(event) {
        const memberId = event.target.dataset.id;
        const setting = event.target.dataset.setting;
        this.data = {
            ...this.data,
            members: this.data.members.map((member) => member.id === memberId
                ? { ...member, [setting]: event.target.checked }
                : member)
        };
    }

    async saveExpense() {
        const fields = [...this.template.querySelectorAll('.modal-body lightning-input, .modal-body lightning-combobox')];
        if (fields.some((field) => !field.reportValidity())) return;
        this.isSaving = true;
        try {
            if (this.editingExpenseId) {
                await updateExpense({
                    expenseId: this.editingExpenseId,
                    label: this.newExpense.label,
                    expenseName: this.newExpense.name,
                    amount: Number(this.newExpense.amount)
                });
            } else {
                await addExpense({ label: this.newExpense.label, expenseName: this.newExpense.name, amount: Number(this.newExpense.amount) });
            }
            const wasEditing = Boolean(this.editingExpenseId);
            this.showExpenseModal = false;
            this.editingExpenseId = undefined;
            this.toast(wasEditing ? 'Expense updated' : 'Expense added', wasEditing ? 'The expense changes were saved.' : 'The expense was recorded under your name.', 'success');
            await this.refresh(wasEditing ? this.selectedMonth : '');
        } catch (error) {
            this.toast(this.editingExpenseId ? 'Could not update expense' : 'Could not save expense', this.getError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleDeleteExpense(event) {
        const expenseId = event.currentTarget.dataset.id;
        const confirmed = await LightningConfirm.open({
            label: 'Delete expense',
            message: 'Delete this expense? This cannot be undone.',
            variant: 'header'
        });
        if (!confirmed) return;
        this.isSaving = true;
        try {
            await deleteExpenseRecord({ expenseId });
            this.toast('Expense deleted', 'The expense was removed.', 'success');
            await this.refresh(this.selectedMonth);
        } catch (error) {
            this.toast('Could not delete expense', this.getError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async saveAdminSettings() {
        this.isSaving = true;
        this.adminSaveMessage = '';
        try {
            const updates = (this.data?.members || []).map((member) => ({
                id: member.id,
                includeRent: member.includeRent,
                includeExpenses: member.includeExpenses
            }));
            await saveAdminSettings({ updates, rentAmount: Number(this.rentInput), payeeUpiId: this.upiInput });
            this.adminSaveMessage = 'Settings saved.';
            this.toast('Settings saved', 'Rent, expense participation, and rent amount were updated.', 'success');
            await this.refresh();
        } catch (error) {
            this.adminSaveMessage = this.getError(error);
            this.toast('Could not save settings', this.getError(error), 'error');
        } finally {
            this.isSaving = false;
        }
    }

    async handleSendReport() {
        const confirmed = await LightningConfirm.open({
            label: 'Send monthly report',
            message: `Send the ${this.reportMonthLabel} report to all linked roommate users now?`,
            variant: 'header'
        });
        if (!confirmed) return;
        this.isSendingReport = true;
        this.reportMessage = 'Sending report...';
        try {
            this.reportMessage = await sendMonthlyReport({ monthKey: this.reportMonth });
            this.toast('Monthly report', this.reportMessage, 'success');
        } catch (error) {
            this.reportMessage = this.getError(error);
            this.toast('Could not send report', this.reportMessage, 'error');
        } finally {
            this.isSendingReport = false;
        }
    }

    toast(title, message, variant) { Toast.show({ label: title, message, variant }, this); }
}