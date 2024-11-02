class ModalWindow {
    #modal = null;
    #modalBody = null;
    constructor(modalElement) {
        if(!(modalElement instanceof HTMLElement)) {
            throw new Error("element must be an HTMLElement or string with the id of the element");
        }
        this.#modal = modalElement;
        this.#modal.querySelector("div.modal-header div.close").addEventListener("click", this.close.bind(this));
        this.#modalBody = this.#modal.querySelector("div.modal-body");
        this.modalContent = document.querySelector('.modal-content');
    }




    removeAllElements() {
        this.#modalBody.innerHTML = "";
    }

    addElement(element) {
        this.#modalBody.appendChild(element);
    }

    getModalBodyElement() {
        return this.#modalBody;
    }

    open() {
        this.#modal.classList.add('show');
    }

    close() {
        this.#modal.classList.remove('show');
    }
}
